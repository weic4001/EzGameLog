import CryptoKit
import Foundation

actor SessionStore {
    private var rootDirectory: URL
    private var activePaths: [UUID: SessionPaths] = [:]
    private var activeMetadata: [UUID: DebugSession] = [:]
    private var logHandles: [UUID: FileHandle] = [:]

    init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/GameLog/Sessions", directoryHint: .isDirectory)
    }

    func updateRootDirectory(_ url: URL) throws {
        guard activePaths.isEmpty else {
            throw SessionStoreError.activeSessionsPreventDirectoryChange
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        rootDirectory = url
    }

    func create(
        device: AndroidDevice,
        targetPackage: String,
        pids: [Int],
        adbPath: String,
        adbVersion: String,
        buffers: Set<LogBufferName> = [.main, .system, .crash],
        initialPreset: LogPreset,
        initialFilterConfiguration: LogFilterConfiguration? = nil
    ) throws -> (DebugSession, SessionPaths) {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let session = DebugSession(
            id: UUID(),
            createdAt: Date(),
            endedAt: nil,
            timeZoneIdentifier: TimeZone.current.identifier,
            device: device,
            targetPackage: targetPackage,
            initialPIDs: pids,
            adbPath: adbPath,
            adbVersion: adbVersion,
            buffers: buffers.sorted { $0.rawValue < $1.rawValue },
            initialPreset: initialPreset,
            initialFilterConfiguration: initialFilterConfiguration,
            artifacts: []
        )
        let paths = makePaths(for: session)

        do {
            try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: paths.screenshotsDirectory, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: paths.recordingsDirectory, withIntermediateDirectories: false)
            guard FileManager.default.createFile(atPath: paths.jsonLinesLog.path, contents: nil),
                  FileManager.default.createFile(atPath: paths.bookmarks.path, contents: Data("[]".utf8)),
                  FileManager.default.createFile(atPath: paths.incidents.path, contents: Data("[]".utf8)),
                  FileManager.default.createFile(atPath: paths.pendingRecordings.path, contents: Data("[]".utf8)),
                  FileManager.default.createFile(atPath: paths.inProgressMarker.path, contents: Data()) else {
                throw SessionStoreError.cannotCreateSession
            }
            try writeMetadata(session, to: paths.metadata)
            let handle = try FileHandle(forWritingTo: paths.jsonLinesLog)
            activePaths[session.id] = paths
            activeMetadata[session.id] = session
            logHandles[session.id] = handle
            return (session, paths)
        } catch {
            try? FileManager.default.removeItem(at: paths.root)
            throw error
        }
    }

    func append(events: [LogEvent], sessionID: UUID) throws {
        guard !events.isEmpty else { return }
        let encoder = Self.makeEncoder()
        var data = Data()
        for event in events {
            data.append(try encoder.encode(event))
            data.append(0x0A)
        }
        if let handle = logHandles[sessionID] {
            try handle.write(contentsOf: data)
            invalidateAnalysis(sessionID: sessionID)
            return
        }
        let paths = try paths(for: sessionID)
        let handle = try FileHandle(forWritingTo: paths.jsonLinesLog)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        invalidateAnalysis(sessionID: sessionID)
    }

    func mergeObservedTargetPIDs(_ pids: Set<Int>, sessionID: UUID) throws {
        guard !pids.isEmpty else { return }
        let paths = try paths(for: sessionID)
        var metadata = try metadata(for: sessionID, paths: paths)
        let merged = metadata.diagnosticTargetPIDs.union(pids).sorted()
        guard merged != metadata.observedPIDs else { return }
        metadata.observedPIDs = merged
        if activeMetadata[sessionID] != nil {
            activeMetadata[sessionID] = metadata
        }
        try writeMetadata(metadata, to: paths.metadata)
        invalidateAnalysis(sessionID: sessionID)
    }

    func append(artifact evidence: CaptureEvidence, sessionID: UUID) throws {
        let paths = try paths(for: sessionID)
        var metadata = try metadata(for: sessionID, paths: paths)
        let relativePath = evidence.fileURL.path.replacingOccurrences(
            of: paths.root.path + "/",
            with: ""
        )
        let thumbnailRelativePath = evidence.thumbnailURL?.path.replacingOccurrences(
            of: paths.root.path + "/",
            with: ""
        )
        let attributes = try? FileManager.default.attributesOfItem(atPath: evidence.fileURL.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.int64Value
        metadata.artifacts.append(SessionArtifact(
            id: evidence.id,
            kind: evidence.kind,
            relativePath: relativePath,
            thumbnailRelativePath: thumbnailRelativePath,
            createdAt: evidence.createdAt,
            duration: evidence.duration,
            byteCount: evidence.byteCount ?? byteCount,
            pixelWidth: evidence.pixelWidth,
            pixelHeight: evidence.pixelHeight,
            remotePath: evidence.remotePath
        ))
        if activeMetadata[sessionID] != nil {
            activeMetadata[sessionID] = metadata
        }
        try writeMetadata(metadata, to: paths.metadata)
        invalidateAnalysis(sessionID: sessionID)
    }

    func append(recoverableRecording: RecoverableRecording, sessionID: UUID) throws {
        let paths = try paths(for: sessionID)
        var recoverable = try recoverableRecordings(sessionID: sessionID)
        recoverable.removeAll { $0.id == recoverableRecording.id }
        recoverable.append(recoverableRecording)
        try Self.makeEncoder().encode(recoverable).write(
            to: paths.pendingRecordings,
            options: .atomic
        )
    }

    func recoverableRecordings(sessionID: UUID) throws -> [RecoverableRecording] {
        let paths = try paths(for: sessionID)
        guard FileManager.default.fileExists(atPath: paths.pendingRecordings.path) else { return [] }
        return try Self.makeDecoder().decode(
            [RecoverableRecording].self,
            from: Data(contentsOf: paths.pendingRecordings)
        )
    }

    func removeRecoverableRecording(id: UUID, sessionID: UUID) throws {
        let paths = try paths(for: sessionID)
        var recoverable = try recoverableRecordings(sessionID: sessionID)
        recoverable.removeAll { $0.id == id }
        try Self.makeEncoder().encode(recoverable).write(
            to: paths.pendingRecordings,
            options: .atomic
        )
    }

    func updateBookmarks(_ eventIDs: Set<UUID>, sessionID: UUID) throws {
        let paths: SessionPaths
        if let active = activePaths[sessionID] {
            paths = active
        } else if let directory = try sessionDirectory(id: sessionID) {
            paths = makePaths(root: directory)
        } else {
            throw SessionStoreError.sessionNotFound
        }
        try JSONEncoder().encode(eventIDs).write(to: paths.bookmarks, options: .atomic)
    }

    func bookmarks(sessionID: UUID) throws -> Set<UUID> {
        let paths: SessionPaths
        if let active = activePaths[sessionID] {
            paths = active
        } else if let directory = try sessionDirectory(id: sessionID) {
            paths = makePaths(root: directory)
        } else {
            throw SessionStoreError.sessionNotFound
        }
        guard FileManager.default.fileExists(atPath: paths.bookmarks.path) else { return [] }
        return try JSONDecoder().decode(Set<UUID>.self, from: Data(contentsOf: paths.bookmarks))
    }

    func upsert(incident: IncidentRecord, sessionID: UUID) throws {
        let paths = try paths(for: sessionID)
        var values = try incidents(sessionID: sessionID)
        if let index = values.firstIndex(where: { $0.id == incident.id }) {
            values[index] = incident
        } else {
            values.append(incident)
        }
        values.sort { $0.createdAt < $1.createdAt }
        try Self.makeMetadataEncoder().encode(values).write(
            to: paths.incidents,
            options: .atomic
        )
        invalidateAnalysis(sessionID: sessionID)
    }

    func incidents(sessionID: UUID) throws -> [IncidentRecord] {
        let paths = try paths(for: sessionID)
        guard FileManager.default.fileExists(atPath: paths.incidents.path) else { return [] }
        return try Self.makeDecoder().decode(
            [IncidentRecord].self,
            from: Data(contentsOf: paths.incidents)
        )
    }

    func flush(sessionID: UUID) throws {
        guard let handle = logHandles[sessionID] else { return }
        try handle.synchronize()
    }

    func finalize(sessionID: UUID, endedAt: Date = Date()) throws -> DebugSession {
        guard var metadata = activeMetadata[sessionID],
              let paths = activePaths[sessionID] else {
            throw SessionStoreError.sessionNotActive
        }
        try flush(sessionID: sessionID)
        try logHandles[sessionID]?.close()
        logHandles[sessionID] = nil
        metadata.endedAt = endedAt
        try writeMetadata(metadata, to: paths.metadata)
        if FileManager.default.fileExists(atPath: paths.inProgressMarker.path) {
            try FileManager.default.removeItem(at: paths.inProgressMarker)
        }
        activeMetadata[sessionID] = nil
        activePaths[sessionID] = nil
        return metadata
    }

    func finalizeRecovered(sessionID: UUID, endedAt: Date = Date()) throws -> DebugSession {
        let paths = try paths(for: sessionID)
        var metadata = try metadata(for: sessionID, paths: paths)
        if metadata.endedAt == nil {
            metadata.endedAt = endedAt
            try writeMetadata(metadata, to: paths.metadata)
        }
        if FileManager.default.fileExists(atPath: paths.inProgressMarker.path) {
            try FileManager.default.removeItem(at: paths.inProgressMarker)
        }
        return metadata
    }

    func recoverableSessions() throws -> [RecoverableSession] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else { return [] }
        let directories = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let decoder = Self.makeDecoder()
        return directories.compactMap { directory in
            let paths = makePaths(root: directory)
            guard FileManager.default.fileExists(atPath: paths.inProgressMarker.path),
                  let data = try? Data(contentsOf: paths.metadata),
                  let session = try? decoder.decode(DebugSession.self, from: data) else {
                return nil
            }
            return RecoverableSession(session: session, paths: paths)
        }
        .sorted { $0.session.createdAt > $1.session.createdAt }
    }

    func archiveEntries() throws -> [SessionArchiveEntry] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else { return [] }
        let directories = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let decoder = Self.makeDecoder()
        return directories.compactMap { directory in
            let paths = makePaths(root: directory)
            guard let data = try? Data(contentsOf: paths.metadata),
                  let session = try? decoder.decode(DebugSession.self, from: data) else {
                return nil
            }
            let logBytes = ((try? FileManager.default.attributesOfItem(
                atPath: paths.jsonLinesLog.path
            )[.size]) as? NSNumber)?.int64Value ?? 0
            let incidentCount = (try? incidents(sessionID: session.id).count) ?? 0
            let annotation = (try? annotation(sessionID: session.id)) ?? .empty
            return SessionArchiveEntry(
                session: session,
                directoryURL: directory,
                logByteCount: logBytes,
                incidentCount: incidentCount,
                annotation: annotation,
                isInProgress: FileManager.default.fileExists(
                    atPath: paths.inProgressMarker.path
                )
            )
        }
        .sorted { $0.session.createdAt > $1.session.createdAt }
    }

    func annotation(sessionID: UUID) throws -> SessionAnnotation {
        let paths = try paths(for: sessionID)
        guard FileManager.default.fileExists(atPath: paths.annotation.path) else {
            return .empty
        }
        return try Self.makeDecoder().decode(
            SessionAnnotation.self,
            from: Data(contentsOf: paths.annotation)
        )
    }

    func updateAnnotation(_ annotation: SessionAnnotation, sessionID: UUID) throws {
        let paths = try paths(for: sessionID)
        var normalized = annotation
        normalized.title = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.note = normalized.note.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.labels = Array(Set(normalized.labels.compactMap { label in
            let value = label.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }))
        .sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        normalized.updatedAt = Date()
        try Self.makeMetadataEncoder().encode(normalized).write(
            to: paths.annotation,
            options: .atomic
        )
    }

    func analysis(sessionID: UUID, forceRefresh: Bool = false) throws -> SessionAnalysisSnapshot {
        let paths = try paths(for: sessionID)
        let metadata = try metadata(for: sessionID, paths: paths)
        if !forceRefresh,
           metadata.endedAt != nil,
           FileManager.default.fileExists(atPath: paths.analysis.path),
           let cached = try? Self.makeDecoder().decode(
               SessionAnalysisSnapshot.self,
               from: Data(contentsOf: paths.analysis)
           ),
           cached.formatVersion == 2 {
            return cached
        }
        let events = try readEvents(from: paths.jsonLinesLog)
        let incidentCount = (try? incidents(sessionID: sessionID).count) ?? 0
        let logBytes = ((try? FileManager.default.attributesOfItem(
            atPath: paths.jsonLinesLog.path
        )[.size]) as? NSNumber)?.int64Value ?? 0
        let snapshot = SessionAnalysisService.snapshot(
            session: metadata,
            events: events,
            incidentCount: incidentCount,
            logByteCount: logBytes
        )
        if metadata.endedAt != nil {
            try Self.makeMetadataEncoder().encode(snapshot).write(
                to: paths.analysis,
                options: .atomic
            )
        }
        return snapshot
    }

    func analysisSnapshots(forceRefresh: Bool = false) throws -> [SessionAnalysisSnapshot] {
        try archiveEntries().compactMap { entry in
            try? analysis(sessionID: entry.id, forceRefresh: forceRefresh)
        }
    }

    func symbolicationReport(sessionID: UUID) throws -> SessionSymbolicationReport? {
        let paths = try paths(for: sessionID)
        guard FileManager.default.fileExists(atPath: paths.symbolication.path) else {
            return nil
        }
        return try Self.makeDecoder().decode(
            SessionSymbolicationReport.self,
            from: Data(contentsOf: paths.symbolication)
        )
    }

    func saveSymbolicationReport(
        _ report: SessionSymbolicationReport,
        sessionID: UUID
    ) throws {
        guard report.sessionID == sessionID else {
            throw SessionStoreError.invalidSymbolicationReport
        }
        let paths = try paths(for: sessionID)
        try Self.makeMetadataEncoder().encode(report).write(
            to: paths.symbolication,
            options: .atomic
        )
    }

    func symbolicationReports() throws -> [UUID: SessionSymbolicationReport] {
        var values: [UUID: SessionSymbolicationReport] = [:]
        for entry in try archiveEntries() {
            if let report = try? symbolicationReport(sessionID: entry.id) {
                values[entry.id] = report
            }
        }
        return values
    }

    func regressionBaselines() throws -> [RegressionBaseline] {
        let url = rootDirectory.appending(path: ".regression-baselines.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Self.makeDecoder().decode(
            [RegressionBaseline].self,
            from: Data(contentsOf: url)
        )
    }

    func regressionConfigurations() throws -> [RegressionConfiguration] {
        let url = rootDirectory.appending(path: ".regression-configurations.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Self.makeDecoder().decode(
            [RegressionConfiguration].self,
            from: Data(contentsOf: url)
        )
    }

    @discardableResult
    func updateRegressionConfiguration(
        _ configuration: RegressionConfiguration
    ) throws -> RegressionConfiguration {
        guard AndroidPackageName.isValid(configuration.targetPackage) else {
            throw SessionStoreError.invalidRegressionConfiguration
        }
        var normalized = configuration
        normalized.thresholds = normalized.thresholds.normalized()
        normalized.updatedAt = Date()
        var values = try regressionConfigurations()
        values.removeAll { $0.targetPackage == normalized.targetPackage }
        values.append(normalized)
        values.sort {
            $0.targetPackage.localizedStandardCompare($1.targetPackage)
                == .orderedAscending
        }
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try Self.makeMetadataEncoder().encode(values).write(
            to: rootDirectory.appending(path: ".regression-configurations.json"),
            options: .atomic
        )
        return normalized
    }

    @discardableResult
    func setRegressionBaseline(sessionID: UUID) throws -> RegressionBaseline {
        let metadata = try metadata(
            for: sessionID,
            paths: try paths(for: sessionID)
        )
        var values = try regressionBaselines()
        let baseline = RegressionBaseline(
            targetPackage: metadata.targetPackage,
            sessionID: sessionID,
            updatedAt: Date()
        )
        values.removeAll { $0.targetPackage == metadata.targetPackage }
        values.append(baseline)
        values.sort {
            $0.targetPackage.localizedStandardCompare($1.targetPackage)
                == .orderedAscending
        }
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try Self.makeMetadataEncoder().encode(values).write(
            to: rootDirectory.appending(path: ".regression-baselines.json"),
            options: .atomic
        )
        return baseline
    }

    func previewImport(from selectedDirectory: URL) throws -> SessionImportPreview {
        try prepareImport(from: selectedDirectory).preview
    }

    func importSession(from selectedDirectory: URL) throws -> SessionImportResult {
        let prepared = try prepareImport(from: selectedDirectory)
        let sourcePaths = prepared.sourcePaths
        let sourceSession = prepared.sourceSession
        let eventCount = prepared.eventCount
        let importedAnnotation = prepared.importedAnnotation

        if prepared.preview.disposition == .mergeAnnotation {
            let existingPaths = try paths(for: sourceSession.id)
            let localAnnotation = (try? annotation(sessionID: sourceSession.id))
                ?? .empty
            let merged = Self.mergeAnnotations(
                local: localAnnotation,
                imported: importedAnnotation
            )
            try Self.makeMetadataEncoder().encode(merged).write(
                to: existingPaths.annotation,
                options: .atomic
            )
            return SessionImportResult(
                sessionID: sourceSession.id,
                targetPackage: sourceSession.targetPackage,
                disposition: .mergedAnnotation,
                importedEventCount: 0,
                mergedLabelCount: merged.labels.count
            )
        }

        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        var importedSession = sourceSession
        if importedSession.endedAt == nil {
            importedSession.endedAt = Date()
        }
        let finalPaths = makePaths(for: importedSession)
        guard !FileManager.default.fileExists(atPath: finalPaths.root.path) else {
            throw SessionStoreError.duplicateSessionIdentityConflict
        }
        let temporaryRoot = rootDirectory.appending(
            path: ".GameLog-import-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let temporaryPaths = makePaths(root: temporaryRoot)
        do {
            try FileManager.default.createDirectory(
                at: temporaryRoot,
                withIntermediateDirectories: false
            )
            try FileManager.default.createDirectory(
                at: temporaryPaths.screenshotsDirectory,
                withIntermediateDirectories: false
            )
            try FileManager.default.createDirectory(
                at: temporaryPaths.recordingsDirectory,
                withIntermediateDirectories: false
            )
            try writeMetadata(importedSession, to: temporaryPaths.metadata)
            try FileManager.default.copyItem(
                at: sourcePaths.jsonLinesLog,
                to: temporaryPaths.jsonLinesLog
            )
            try copyValidatedJSONIfPresent(
                source: sourcePaths.bookmarks,
                destination: temporaryPaths.bookmarks,
                type: Set<UUID>.self,
                fallback: Set<UUID>()
            )
            try copyValidatedJSONIfPresent(
                source: sourcePaths.incidents,
                destination: temporaryPaths.incidents,
                type: [IncidentRecord].self,
                fallback: [IncidentRecord]()
            )
            if importedAnnotation != .empty {
                try Self.makeMetadataEncoder().encode(importedAnnotation).write(
                    to: temporaryPaths.annotation,
                    options: .atomic
                )
            }
            try Self.makeMetadataEncoder().encode([RecoverableRecording]()).write(
                to: temporaryPaths.pendingRecordings,
                options: .atomic
            )
            try copyValidatedDirectoryContents(
                from: sourcePaths.screenshotsDirectory,
                to: temporaryPaths.screenshotsDirectory
            )
            try copyValidatedDirectoryContents(
                from: sourcePaths.recordingsDirectory,
                to: temporaryPaths.recordingsDirectory
            )
            try FileManager.default.moveItem(
                at: temporaryRoot,
                to: finalPaths.root
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryRoot)
            throw error
        }
        return SessionImportResult(
            sessionID: importedSession.id,
            targetPackage: importedSession.targetPackage,
            disposition: .imported,
            importedEventCount: eventCount,
            mergedLabelCount: importedAnnotation.labels.count
        )
    }

    private func prepareImport(
        from selectedDirectory: URL
    ) throws -> PreparedSessionImport {
        let sourceRoot = try resolveImportRoot(selectedDirectory)
        let sourcePaths = makePaths(root: sourceRoot)
        guard FileManager.default.fileExists(atPath: sourcePaths.metadata.path),
              FileManager.default.fileExists(atPath: sourcePaths.jsonLinesLog.path) else {
            throw SessionStoreError.invalidImportPackage
        }
        try validateRegularFile(sourcePaths.metadata)
        try validateRegularFile(sourcePaths.jsonLinesLog)
        let tree = try validateImportTree(root: sourceRoot)
        let sourceSession = try decodeImportJSON(
            DebugSession.self,
            from: sourcePaths.metadata
        )
        guard AndroidPackageName.isValid(sourceSession.targetPackage) else {
            throw SessionStoreError.invalidImportPackage
        }
        let eventCount = try validateImportEvents(at: sourcePaths.jsonLinesLog)
        let integrityStatus = try validateCollaborationManifest(
            root: sourceRoot,
            session: sourceSession
        )
        try validateImportedArtifacts(sourceSession.artifacts, root: sourceRoot)
        let importedAnnotation = try importedAnnotation(from: sourcePaths.annotation)

        let disposition: SessionImportPreviewDisposition
        if let existingDirectory = try sessionDirectory(id: sourceSession.id) {
            guard activePaths[sourceSession.id] == nil else {
                throw SessionStoreError.importConflictsWithActiveSession
            }
            let existingPaths = makePaths(root: existingDirectory)
            let existing = try metadata(
                for: sourceSession.id,
                paths: existingPaths
            )
            guard existing.targetPackage == sourceSession.targetPackage,
                  existing.device.serial == sourceSession.device.serial,
                  existing.createdAt == sourceSession.createdAt else {
                throw SessionStoreError.duplicateSessionIdentityConflict
            }
            disposition = .mergeAnnotation
        } else {
            disposition = .newSession
        }

        let preview = SessionImportPreview(
            sourceURL: sourceRoot,
            sessionID: sourceSession.id,
            targetPackage: sourceSession.targetPackage,
            deviceDisplayName: sourceSession.device.displayName,
            deviceSerial: sourceSession.device.serial,
            createdAt: sourceSession.createdAt,
            endedAt: sourceSession.endedAt,
            eventCount: eventCount,
            artifactCount: sourceSession.artifacts.count,
            screenshotCount: sourceSession.artifacts.lazy.filter {
                $0.kind == .screenshot
            }.count,
            recordingCount: sourceSession.artifacts.lazy.filter {
                $0.kind == .recording
            }.count,
            totalByteCount: tree.byteCount,
            integrityStatus: integrityStatus,
            disposition: disposition,
            importedTitle: importedAnnotation.title,
            importedLabels: importedAnnotation.labels
        )
        return PreparedSessionImport(
            sourcePaths: sourcePaths,
            sourceSession: sourceSession,
            eventCount: eventCount,
            importedAnnotation: importedAnnotation,
            preview: preview
        )
    }

    func load(
        sessionID: UUID,
        retainingLast eventLimit: Int? = nil
    ) throws -> (DebugSession, SessionPaths, [LogEvent], [CaptureEvidence]) {
        let paths: SessionPaths
        if let active = activePaths[sessionID] {
            paths = active
        } else {
            guard let directory = try sessionDirectory(id: sessionID) else {
                throw SessionStoreError.sessionNotFound
            }
            paths = makePaths(root: directory)
        }
        let metadataData = try Data(contentsOf: paths.metadata)
        let metadata = try Self.makeDecoder().decode(DebugSession.self, from: metadataData)
        let events = try readEvents(
            from: paths.jsonLinesLog,
            retainingLast: eventLimit
        )
        let evidence = metadata.artifacts.map { artifact in
            CaptureEvidence(
                id: artifact.id,
                kind: artifact.kind,
                fileURL: paths.root.appending(path: artifact.relativePath),
                thumbnailURL: artifact.thumbnailRelativePath.map { paths.root.appending(path: $0) },
                createdAt: artifact.createdAt,
                deviceSerial: metadata.device.serial,
                duration: artifact.duration,
                pixelWidth: artifact.pixelWidth,
                pixelHeight: artifact.pixelHeight,
                byteCount: artifact.byteCount,
                remotePath: artifact.remotePath
            )
        }
        return (metadata, paths, events, evidence)
    }

    func discard(sessionID: UUID) throws {
        if let handle = logHandles[sessionID] {
            try? handle.close()
            logHandles[sessionID] = nil
        }
        let directory: URL?
        if let activeRoot = activePaths[sessionID]?.root {
            directory = activeRoot
        } else {
            directory = try sessionDirectory(id: sessionID)
        }
        activePaths[sessionID] = nil
        activeMetadata[sessionID] = nil
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func export(
        sessionID: UUID,
        scope: SessionExportScope,
        destinationDirectory: URL,
        redactionConfiguration: RedactionConfiguration = .disabled
    ) throws -> URL {
        try flush(sessionID: sessionID)
        let sourcePaths = try paths(for: sessionID)
        let metadata = try metadata(for: sessionID, paths: sourcePaths)
        let sourceEvents: [LogEvent]
        switch scope {
        case .wholeSession:
            sourceEvents = try readEvents(from: sourcePaths.jsonLinesLog)
        case .filtered(let filtered):
            sourceEvents = filtered
        case .selected(let selected):
            sourceEvents = selected
        }
        let exportedEvents = sourceEvents.map {
            LogRedactor.redact(
                event: $0,
                configuration: redactionConfiguration,
                deviceSerial: metadata.device.serial
            )
        }
        let exportedMetadata = LogRedactor.redactedSession(
            metadata,
            configuration: redactionConfiguration
        )

        let finalURL = availableExportURL(for: metadata, in: destinationDirectory)
        let temporaryURL = destinationDirectory.appending(
            path: ".GameLog-export-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        do {
            try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: false)
            let screenshots = temporaryURL.appending(path: "screenshots", directoryHint: .isDirectory)
            let recordings = temporaryURL.appending(path: "recordings", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: false)
            try writeMetadata(exportedMetadata, to: temporaryURL.appending(path: "session.json"))
            let exportedJSONLines = temporaryURL.appending(path: "logs.jsonl")
            let exportedPlainText = temporaryURL.appending(path: "logs.txt")
            if case .wholeSession = scope, !redactionConfiguration.isEnabled {
                try FileManager.default.copyItem(
                    at: sourcePaths.jsonLinesLog,
                    to: exportedJSONLines
                )
                try writePlainText(
                    fromJSONLines: sourcePaths.jsonLinesLog,
                    to: exportedPlainText
                )
            } else {
                try write(events: exportedEvents, toJSONLines: exportedJSONLines)
                try writePlainText(events: exportedEvents, to: exportedPlainText)
            }
            if FileManager.default.fileExists(atPath: sourcePaths.bookmarks.path) {
                try FileManager.default.copyItem(
                    at: sourcePaths.bookmarks,
                    to: temporaryURL.appending(path: "bookmarks.json")
                )
            }
            if FileManager.default.fileExists(atPath: sourcePaths.annotation.path) {
                try FileManager.default.copyItem(
                    at: sourcePaths.annotation,
                    to: temporaryURL.appending(path: "annotation.json")
                )
            }
            let storedIncidents = try incidents(sessionID: sessionID)
            let exportedIncidents = storedIncidents.map {
                LogRedactor.redact(
                    incident: $0,
                    configuration: redactionConfiguration,
                    deviceSerial: metadata.device.serial
                )
            }
            try Self.makeMetadataEncoder().encode(exportedIncidents).write(
                to: temporaryURL.appending(path: "incidents.json"),
                options: .atomic
            )
            let diagnostics = DiagnosticAggregator.aggregate(
                events: exportedEvents,
                targetPIDs: metadata.diagnosticTargetPIDs,
                targetPackage: metadata.targetPackage
            )
            try Self.makeMetadataEncoder().encode(diagnostics).write(
                to: temporaryURL.appending(path: "diagnostics.json"),
                options: .atomic
            )
            try Self.makeMetadataEncoder().encode(redactionConfiguration).write(
                to: temporaryURL.appending(path: "redaction.json"),
                options: .atomic
            )
            if FileManager.default.fileExists(atPath: sourcePaths.pendingRecordings.path) {
                try FileManager.default.copyItem(
                    at: sourcePaths.pendingRecordings,
                    to: temporaryURL.appending(path: "pending-recordings.json")
                )
            }
            try copyDirectoryContents(from: sourcePaths.screenshotsDirectory, to: screenshots)
            try copyDirectoryContents(from: sourcePaths.recordingsDirectory, to: recordings)
            try writeCollaborationManifest(
                to: temporaryURL,
                sessionID: metadata.id,
                scope: scope
            )
            try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
            return finalURL
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    func exportIncident(
        sessionID: UUID,
        incidentID: UUID,
        destinationDirectory: URL,
        redactionConfiguration: RedactionConfiguration = .recommended
    ) throws -> URL {
        try flush(sessionID: sessionID)
        let sourcePaths = try paths(for: sessionID)
        let metadata = try metadata(for: sessionID, paths: sourcePaths)
        guard let incident = try incidents(sessionID: sessionID)
            .first(where: { $0.id == incidentID }) else {
            throw SessionStoreError.incidentNotFound
        }
        let lowerBound = incident.createdAt.addingTimeInterval(-incident.logWindowBefore)
        let upperBound = incident.createdAt.addingTimeInterval(incident.logWindowAfter)
        let sourceEvents = try readEvents(from: sourcePaths.jsonLinesLog).filter {
            $0.occurredAt >= lowerBound && $0.occurredAt <= upperBound
        }
        let exportedEvents = sourceEvents.map {
            LogRedactor.redact(
                event: $0,
                configuration: redactionConfiguration,
                deviceSerial: metadata.device.serial
            )
        }
        let exportedMetadata = LogRedactor.redactedSession(
            metadata,
            configuration: redactionConfiguration
        )
        let exportedIncident = LogRedactor.redact(
            incident: incident,
            configuration: redactionConfiguration,
            deviceSerial: metadata.device.serial
        )
        let diagnostics = DiagnosticAggregator.aggregate(
            events: exportedEvents,
            targetPIDs: metadata.diagnosticTargetPIDs,
            targetPackage: metadata.targetPackage
        )
        let manifest = IncidentPackageManifest(
            generatedAt: Date(),
            incident: exportedIncident,
            sessionID: metadata.id,
            targetPackage: metadata.targetPackage,
            deviceDisplayName: metadata.device.displayName,
            diagnosticIssues: diagnostics,
            redactionApplied: redactionConfiguration.isEnabled
        )

        let finalURL = availableIncidentExportURL(for: incident, in: destinationDirectory)
        let temporaryURL = destinationDirectory.appending(
            path: ".GameLog-incident-export-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        do {
            try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: false)
            let screenshots = temporaryURL.appending(path: "screenshots", directoryHint: .isDirectory)
            let recordings = temporaryURL.appending(path: "recordings", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: false)
            try writeMetadata(exportedMetadata, to: temporaryURL.appending(path: "session.json"))
            try Self.makeMetadataEncoder().encode(manifest).write(
                to: temporaryURL.appending(path: "incident.json"),
                options: .atomic
            )
            try write(events: exportedEvents, toJSONLines: temporaryURL.appending(path: "logs.jsonl"))
            try writePlainText(events: exportedEvents, to: temporaryURL.appending(path: "logs.txt"))
            try Self.makeMetadataEncoder().encode(diagnostics).write(
                to: temporaryURL.appending(path: "diagnostics.json"),
                options: .atomic
            )
            try Self.makeMetadataEncoder().encode(redactionConfiguration).write(
                to: temporaryURL.appending(path: "redaction.json"),
                options: .atomic
            )

            let explicitEvidenceIDs = Set(
                incident.evidenceIDs + [incident.recordingID].compactMap { $0 }
            )
            for artifact in metadata.artifacts {
                let recordingContainsIncident = artifact.kind == .recording
                    && artifact.createdAt <= incident.createdAt
                    && incident.createdAt <= artifact.createdAt.addingTimeInterval(artifact.duration ?? 0)
                let nearbyScreenshot = artifact.kind == .screenshot
                    && abs(artifact.createdAt.timeIntervalSince(incident.createdAt)) <= 5
                guard explicitEvidenceIDs.contains(artifact.id)
                    || recordingContainsIncident
                    || nearbyScreenshot else {
                    continue
                }
                let source = sourcePaths.root.appending(path: artifact.relativePath)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                let destination = artifact.kind == .screenshot ? screenshots : recordings
                try FileManager.default.copyItem(
                    at: source,
                    to: destination.appending(path: source.lastPathComponent)
                )
            }
            try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
            return finalURL
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    func redactionPreview(
        sessionID: UUID,
        scope: SessionExportScope,
        configuration: RedactionConfiguration = .recommended
    ) throws -> RedactionPreview {
        try flush(sessionID: sessionID)
        let sourcePaths = try paths(for: sessionID)
        let metadata = try metadata(for: sessionID, paths: sourcePaths)
        let sourceEvents: [LogEvent]
        switch scope {
        case .wholeSession:
            sourceEvents = try readEvents(from: sourcePaths.jsonLinesLog)
        case .filtered(let filtered):
            sourceEvents = filtered
        case .selected(let selected):
            sourceEvents = selected
        }
        return LogRedactor.preview(
            events: sourceEvents,
            session: metadata,
            configuration: configuration
        )
    }

    func incidentRedactionPreview(
        sessionID: UUID,
        incidentID: UUID,
        configuration: RedactionConfiguration = .recommended
    ) throws -> RedactionPreview {
        let sourcePaths = try paths(for: sessionID)
        let metadata = try metadata(for: sessionID, paths: sourcePaths)
        guard let incident = try incidents(sessionID: sessionID)
            .first(where: { $0.id == incidentID }) else {
            throw SessionStoreError.incidentNotFound
        }
        let lowerBound = incident.createdAt.addingTimeInterval(-incident.logWindowBefore)
        let upperBound = incident.createdAt.addingTimeInterval(incident.logWindowAfter)
        let sourceEvents = try readEvents(from: sourcePaths.jsonLinesLog).filter {
            $0.occurredAt >= lowerBound && $0.occurredAt <= upperBound
        }
        return LogRedactor.preview(
            events: sourceEvents,
            session: metadata,
            configuration: configuration
        )
    }

    func availableCapacity() throws -> Int64 {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let values = try rootDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }

    func cleanupRecoverableSessions(olderThanDays retentionDays: Int?) throws -> Int {
        let recoverable = try recoverableSessions()
        let cutoff = retentionDays.map {
            Calendar.current.date(byAdding: .day, value: -max(0, $0), to: Date()) ?? Date()
        }
        let targets = recoverable.filter { item in
            guard let cutoff else { return true }
            return item.session.createdAt < cutoff
        }
        for item in targets where activePaths[item.id] == nil {
            try FileManager.default.removeItem(at: item.paths.root)
        }
        return targets.count
    }

    private func readEvents(
        from url: URL,
        retainingLast eventLimit: Int? = nil
    ) throws -> [LogEvent] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = Self.makeDecoder()
        var allEvents: [LogEvent] = []
        var boundedBuffer = eventLimit.map { LogBuffer(capacity: max(1, $0)) }
        var batch: [LogEvent] = []
        batch.reserveCapacity(512)

        try forEachLine(in: url) { line in
            guard let event = try? decoder.decode(LogEvent.self, from: line) else {
                return
            }
            batch.append(event)
            guard batch.count >= 512 else { return }
            if boundedBuffer != nil {
                boundedBuffer?.append(contentsOf: batch)
            } else {
                allEvents.append(contentsOf: batch)
            }
            batch.removeAll(keepingCapacity: true)
        }
        if boundedBuffer != nil {
            boundedBuffer?.append(contentsOf: batch)
            return boundedBuffer?.events ?? []
        }
        allEvents.append(contentsOf: batch)
        return allEvents
    }

    private func write(events: [LogEvent], toJSONLines url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw SessionStoreError.cannotCreateSession
        }
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }
        let encoder = Self.makeEncoder()
        var data = Data()
        data.reserveCapacity(1_048_576)
        for event in events {
            data.append(try encoder.encode(event))
            data.append(0x0A)
            if data.count >= 1_048_576 {
                try output.write(contentsOf: data)
                data.removeAll(keepingCapacity: true)
            }
        }
        if !data.isEmpty {
            try output.write(contentsOf: data)
        }
    }

    private func writePlainText(events: [LogEvent], to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw SessionStoreError.cannotCreateSession
        }
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }
        var data = Data()
        data.reserveCapacity(1_048_576)
        for event in events {
            data.append(contentsOf: event.rawText.utf8)
            data.append(0x0A)
            if data.count >= 1_048_576 {
                try output.write(contentsOf: data)
                data.removeAll(keepingCapacity: true)
            }
        }
        if !data.isEmpty {
            try output.write(contentsOf: data)
        }
    }

    private func writePlainText(fromJSONLines source: URL, to destination: URL) throws {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw SessionStoreError.cannotCreateSession
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let decoder = Self.makeDecoder()
        var outputBuffer = Data()
        outputBuffer.reserveCapacity(1_048_576)

        try forEachLine(in: source) { line in
            guard let event = try? decoder.decode(LogEvent.self, from: line) else {
                return
            }
            outputBuffer.append(contentsOf: event.rawText.utf8)
            outputBuffer.append(0x0A)
            if outputBuffer.count >= 1_048_576 {
                try output.write(contentsOf: outputBuffer)
                outputBuffer.removeAll(keepingCapacity: true)
            }
        }
        if !outputBuffer.isEmpty {
            try output.write(contentsOf: outputBuffer)
        }
    }

    private func forEachLine(
        in url: URL,
        _ body: (Data) throws -> Void
    ) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var buffer = Data()

        while let chunk = try input.read(upToCount: 65_536), !chunk.isEmpty {
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                try body(Data(buffer[lineStart..<newline]))
                lineStart = buffer.index(after: newline)
            }
            if lineStart > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<lineStart)
            }
        }
        if !buffer.isEmpty {
            try body(buffer)
        }
    }

    private func copyDirectoryContents(from source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        for item in try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        ) {
            try FileManager.default.copyItem(
                at: item,
                to: destination.appending(path: item.lastPathComponent)
            )
        }
    }

    private func resolveImportRoot(_ selectedDirectory: URL) throws -> URL {
        let selected = selectedDirectory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: selected.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw SessionStoreError.invalidImportPackage
        }
        let selectedValues = try selected.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        guard selectedValues.isDirectory == true,
              selectedValues.isSymbolicLink != true else {
            throw SessionStoreError.unsafeImportPackage
        }
        if FileManager.default.fileExists(
            atPath: selected.appending(path: "session.json").path
        ) {
            return selected
        }
        let children = try FileManager.default.contentsOfDirectory(
            at: selected,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        let candidates = try children.filter {
            let values = try $0.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey
            ])
            return values.isDirectory == true
                && values.isSymbolicLink != true
                && FileManager.default.fileExists(
                    atPath: $0.appending(path: "session.json").path
                )
        }
        guard candidates.count == 1 else {
            throw SessionStoreError.invalidImportPackage
        }
        return candidates[0]
    }

    private func validateRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw SessionStoreError.unsafeImportPackage
        }
    }

    private func validateImportTree(
        root: URL
    ) throws -> (fileCount: Int, byteCount: Int64) {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        let rootValues = try root.resourceValues(forKeys: keys)
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true else {
            throw SessionStoreError.unsafeImportPackage
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            throw SessionStoreError.invalidImportPackage
        }
        let rootPrefix = root.standardizedFileURL.path + "/"
        var fileCount = 0
        var byteCount: Int64 = 0
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true,
                  item.standardizedFileURL.path.hasPrefix(rootPrefix) else {
                throw SessionStoreError.unsafeImportPackage
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw SessionStoreError.unsafeImportPackage
            }
            fileCount += 1
            byteCount += Int64(values.fileSize ?? 0)
            guard fileCount <= 100_000,
                  byteCount <= 50 * 1_024 * 1_024 * 1_024 else {
                throw SessionStoreError.unsafeImportPackage
            }
        }
        return (fileCount, byteCount)
    }

    private func decodeImportJSON<T: Decodable>(
        _ type: T.Type,
        from url: URL
    ) throws -> T {
        try validateRegularFile(url)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 16 * 1_024 * 1_024 else {
            throw SessionStoreError.unsafeImportPackage
        }
        return try Self.makeDecoder().decode(
            type,
            from: Data(contentsOf: url, options: .mappedIfSafe)
        )
    }

    private func validateImportEvents(at url: URL) throws -> Int {
        let decoder = Self.makeDecoder()
        var count = 0
        try forEachLine(in: url) { line in
            guard line.count <= 16 * 1_024 * 1_024 else {
                throw SessionStoreError.unsafeImportPackage
            }
            _ = try decoder.decode(LogEvent.self, from: line)
            count += 1
        }
        return count
    }

    private func validateCollaborationManifest(
        root: URL,
        session: DebugSession
    ) throws -> SessionImportIntegrityStatus {
        let url = root.appending(path: "collaboration-manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .legacyUnverified
        }
        try validateRegularFile(url)
        let manifest = try decodeImportJSON(
            SessionCollaborationManifest.self,
            from: url
        )
        let sessionDigest = try Self.fileSHA256(
            root.appending(path: "session.json")
        )
        let logsDigest = try Self.fileSHA256(
            root.appending(path: "logs.jsonl")
        )
        guard manifest.formatVersion == 2,
              manifest.sessionID == session.id,
              manifest.sessionSHA256 == sessionDigest,
              manifest.logsSHA256 == logsDigest else {
            throw SessionStoreError.importDigestMismatch
        }
        let annotationURL = root.appending(path: "annotation.json")
        let annotationDigest = FileManager.default.fileExists(
            atPath: annotationURL.path
        ) ? try Self.fileSHA256(annotationURL) : nil
        guard manifest.annotationSHA256 == annotationDigest else {
            throw SessionStoreError.importDigestMismatch
        }
        return .verified
    }

    private func validateImportedArtifacts(
        _ artifacts: [SessionArtifact],
        root: URL
    ) throws {
        for artifact in artifacts {
            guard Self.isSafeRelativePath(artifact.relativePath),
                  artifact.thumbnailRelativePath.map(Self.isSafeRelativePath) != false else {
                throw SessionStoreError.unsafeImportPackage
            }
            let file = root.appending(path: artifact.relativePath).standardizedFileURL
            guard file.path.hasPrefix(root.standardizedFileURL.path + "/"),
                  FileManager.default.fileExists(atPath: file.path) else {
                throw SessionStoreError.invalidImportPackage
            }
            try validateRegularFile(file)
            if let thumbnail = artifact.thumbnailRelativePath {
                let thumbnailURL = root.appending(path: thumbnail).standardizedFileURL
                guard thumbnailURL.path.hasPrefix(root.standardizedFileURL.path + "/") else {
                    throw SessionStoreError.unsafeImportPackage
                }
                if FileManager.default.fileExists(atPath: thumbnailURL.path) {
                    try validateRegularFile(thumbnailURL)
                }
            }
        }
    }

    private func importedAnnotation(from url: URL) throws -> SessionAnnotation {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        try validateRegularFile(url)
        return try decodeImportJSON(
            SessionAnnotation.self,
            from: url
        )
    }

    private func copyValidatedJSONIfPresent<T: Codable>(
        source: URL,
        destination: URL,
        type: T.Type,
        fallback: T
    ) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            try Self.makeMetadataEncoder().encode(fallback).write(
                to: destination,
                options: .atomic
            )
            return
        }
        try validateRegularFile(source)
        let decoded = try decodeImportJSON(
            type,
            from: source
        )
        try Self.makeMetadataEncoder().encode(decoded).write(
            to: destination,
            options: .atomic
        )
    }

    private func copyValidatedDirectoryContents(
        from source: URL,
        to destination: URL
    ) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let sourceValues = try source.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        guard sourceValues.isDirectory == true,
              sourceValues.isSymbolicLink != true else {
            throw SessionStoreError.unsafeImportPackage
        }
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: source,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            throw SessionStoreError.invalidImportPackage
        }
        var fileCount = 0
        var byteCount: Int64 = 0
        let sourcePrefix = source.standardizedFileURL.path + "/"
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true,
                  item.standardizedFileURL.path.hasPrefix(sourcePrefix) else {
                throw SessionStoreError.unsafeImportPackage
            }
            let relative = String(
                item.standardizedFileURL.path.dropFirst(sourcePrefix.count)
            )
            guard Self.isSafeRelativePath(relative) else {
                throw SessionStoreError.unsafeImportPackage
            }
            let target = destination.appending(path: relative)
            if values.isDirectory == true {
                try FileManager.default.createDirectory(
                    at: target,
                    withIntermediateDirectories: true
                )
            } else if values.isRegularFile == true {
                fileCount += 1
                byteCount += Int64(values.fileSize ?? 0)
                guard fileCount <= 100_000, byteCount <= 50 * 1_024 * 1_024 * 1_024 else {
                    throw SessionStoreError.unsafeImportPackage
                }
                try FileManager.default.copyItem(at: item, to: target)
            } else {
                throw SessionStoreError.unsafeImportPackage
            }
        }
    }

    private func writeCollaborationManifest(
        to root: URL,
        sessionID: UUID,
        scope: SessionExportScope
    ) throws {
        let sessionURL = root.appending(path: "session.json")
        let logsURL = root.appending(path: "logs.jsonl")
        let annotationURL = root.appending(path: "annotation.json")
        let manifest = SessionCollaborationManifest(
            formatVersion: 2,
            generatedAt: Date(),
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "1.2.2",
            exportScope: {
                switch scope {
                case .wholeSession: "wholeSession"
                case .filtered: "filtered"
                case .selected: "selected"
                }
            }(),
            sessionID: sessionID,
            sessionSHA256: try Self.fileSHA256(sessionURL),
            logsSHA256: try Self.fileSHA256(logsURL),
            annotationSHA256: FileManager.default.fileExists(
                atPath: annotationURL.path
            ) ? try Self.fileSHA256(annotationURL) : nil
        )
        try Self.makeMetadataEncoder().encode(manifest).write(
            to: root.appending(path: "collaboration-manifest.json"),
            options: .atomic
        )
    }

    private static func mergeAnnotations(
        local: SessionAnnotation,
        imported: SessionAnnotation
    ) -> SessionAnnotation {
        guard imported != .empty else { return local }
        let title: String
        if local.title.isEmpty {
            title = imported.title
        } else if imported.title.isEmpty || local.updatedAt >= imported.updatedAt {
            title = local.title
        } else {
            title = imported.title
        }
        let note: String
        if local.note.isEmpty {
            note = imported.note
        } else if imported.note.isEmpty
                    || local.note == imported.note
                    || local.note.contains(imported.note) {
            note = local.note
        } else {
            let timestamp = imported.updatedAt.formatted(
                date: .abbreviated,
                time: .shortened
            )
            note = "\(local.note)\n\n---\n导入注释（\(timestamp)）\n\(imported.note)"
        }
        let labels = Array(Set(local.labels + imported.labels)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        return SessionAnnotation(
            title: title,
            note: note,
            labels: labels,
            updatedAt: max(local.updatedAt, imported.updatedAt)
        )
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.contains("\0") else {
            return false
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    private static func fileSHA256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func availableExportURL(for session: DebugSession, in directory: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "GameLog-Session-\(formatter.string(from: session.createdAt))"
        var candidate = directory.appending(path: base, directoryHint: .isDirectory)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base)-\(suffix)", directoryHint: .isDirectory)
            suffix += 1
        }
        return candidate
    }

    private func availableIncidentExportURL(
        for incident: IncidentRecord,
        in directory: URL
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "GameLog-Issue-\(formatter.string(from: incident.createdAt))"
        var candidate = directory.appending(path: base, directoryHint: .isDirectory)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(
                path: "\(base)-\(suffix)",
                directoryHint: .isDirectory
            )
            suffix += 1
        }
        return candidate
    }

    private func sessionDirectory(id: UUID) throws -> URL? {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else { return nil }
        return try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).first { $0.lastPathComponent.hasSuffix(id.uuidString.lowercased()) }
    }

    private func makePaths(for session: DebugSession) -> SessionPaths {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "GameLog-Session-\(formatter.string(from: session.createdAt))-\(session.id.uuidString.lowercased())"
        return makePaths(root: rootDirectory.appending(path: name, directoryHint: .isDirectory))
    }

    private func makePaths(root: URL) -> SessionPaths {
        SessionPaths(
            root: root,
            metadata: root.appending(path: "session.json"),
            jsonLinesLog: root.appending(path: "logs.jsonl"),
            bookmarks: root.appending(path: "bookmarks.json"),
            incidents: root.appending(path: "incidents.json"),
            annotation: root.appending(path: "annotation.json"),
            analysis: root.appending(path: "analysis.json"),
            symbolication: root.appending(path: "symbolication.json"),
            screenshotsDirectory: root.appending(path: "screenshots", directoryHint: .isDirectory),
            recordingsDirectory: root.appending(path: "recordings", directoryHint: .isDirectory),
            pendingRecordings: root.appending(path: "pending-recordings.json"),
            inProgressMarker: root.appending(path: ".inprogress")
        )
    }

    private func paths(for sessionID: UUID) throws -> SessionPaths {
        if let active = activePaths[sessionID] {
            return active
        }
        guard let directory = try sessionDirectory(id: sessionID) else {
            throw SessionStoreError.sessionNotFound
        }
        return makePaths(root: directory)
    }

    private func invalidateAnalysis(sessionID: UUID) {
        guard let paths = try? paths(for: sessionID) else { return }
        for url in [paths.analysis, paths.symbolication] where
            FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func metadata(for sessionID: UUID, paths: SessionPaths) throws -> DebugSession {
        if let active = activeMetadata[sessionID] {
            return active
        }
        return try Self.makeDecoder().decode(
            DebugSession.self,
            from: Data(contentsOf: paths.metadata)
        )
    }

    private func writeMetadata(_ session: DebugSession, to url: URL) throws {
        try Self.makeMetadataEncoder().encode(session).write(to: url, options: .atomic)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeMetadataEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum SessionStoreError: LocalizedError, Sendable {
    case cannotCreateSession
    case sessionNotActive
    case sessionNotFound
    case incidentNotFound
    case activeSessionsPreventDirectoryChange
    case invalidSymbolicationReport
    case invalidImportPackage
    case unsafeImportPackage
    case importDigestMismatch
    case importConflictsWithActiveSession
    case duplicateSessionIdentityConflict
    case invalidRegressionConfiguration

    var errorDescription: String? {
        switch self {
        case .cannotCreateSession: "无法创建会话目录。"
        case .sessionNotActive: "当前没有可写入的活动会话。"
        case .sessionNotFound: "找不到指定会话。"
        case .incidentNotFound: "找不到指定的问题标记。"
        case .activeSessionsPreventDirectoryChange:
            "仍有活动会话，无法更改共享会话目录。"
        case .invalidSymbolicationReport:
            "符号化报告与会话不匹配。"
        case .invalidImportPackage:
            "所选目录不是有效的 GameLog 会话包。"
        case .unsafeImportPackage:
            "会话包包含符号链接、越界路径或异常大小，已停止导入。"
        case .importDigestMismatch:
            "会话包完整性校验失败，文件可能已被修改或损坏。"
        case .importConflictsWithActiveSession:
            "同一会话仍在采集中，无法合并导入注释。"
        case .duplicateSessionIdentityConflict:
            "发现相同会话 ID，但设备、目标或创建时间不一致。"
        case .invalidRegressionConfiguration:
            "回归规则的目标包或阈值无效。"
        }
    }
}

private struct PreparedSessionImport {
    let sourcePaths: SessionPaths
    let sourceSession: DebugSession
    let eventCount: Int
    let importedAnnotation: SessionAnnotation
    let preview: SessionImportPreview
}
