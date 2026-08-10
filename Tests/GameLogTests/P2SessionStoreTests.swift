import Foundation
import XCTest
@testable import GameLog

final class P2SessionStoreTests: XCTestCase {
    func testImportPreviewIsVerifiedReadOnlyAndDetectsMerge() async throws {
        let roots = try makeRoots()
        defer { roots.cleanup() }
        let source = SessionStore(rootDirectory: roots.source)
        let target = SessionStore(rootDirectory: roots.target)
        let session = try await createFinalizedSession(
            store: source,
            note: "复现步骤",
            labels: ["shared", "android"]
        )
        let exported = try await source.export(
            sessionID: session.id,
            scope: .wholeSession,
            destinationDirectory: roots.export
        )

        let preview = try await target.previewImport(from: exported)

        XCTAssertEqual(preview.sessionID, session.id)
        XCTAssertEqual(preview.targetPackage, "com.example.game")
        XCTAssertEqual(preview.eventCount, 2)
        XCTAssertEqual(preview.integrityStatus, .verified)
        XCTAssertEqual(preview.disposition, .newSession)
        XCTAssertGreaterThan(preview.totalByteCount, 0)
        let entriesBeforeImport = try await target.archiveEntries()
        XCTAssertEqual(entriesBeforeImport.count, 0)

        _ = try await target.importSession(from: exported)
        let mergePreview = try await target.previewImport(from: exported)
        XCTAssertEqual(mergePreview.disposition, .mergeAnnotation)
        XCTAssertEqual(mergePreview.importedLabels, ["android", "shared"])
        let entriesAfterImport = try await target.archiveEntries()
        XCTAssertEqual(entriesAfterImport.count, 1)
    }

    func testExportsIntegrityManifestAndImportsSession() async throws {
        let roots = try makeRoots()
        defer { roots.cleanup() }
        let source = SessionStore(rootDirectory: roots.source)
        let target = SessionStore(rootDirectory: roots.target)
        let session = try await createFinalizedSession(
            store: source,
            note: "来自测试同事",
            labels: ["shared"]
        )
        let exported = try await source.export(
            sessionID: session.id,
            scope: .wholeSession,
            destinationDirectory: roots.export
        )

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: exported.appending(path: "collaboration-manifest.json").path
        ))
        let result = try await target.importSession(from: exported)
        let loaded = try await target.load(sessionID: session.id)
        let importedAnnotation = try await target.annotation(
            sessionID: session.id
        )

        XCTAssertEqual(result.disposition, .imported)
        XCTAssertEqual(result.importedEventCount, 2)
        XCTAssertEqual(loaded.2.map(\.message), ["event-1", "event-2"])
        XCTAssertNotNil(loaded.0.endedAt)
        XCTAssertEqual(importedAnnotation.labels, ["shared"])
    }

    func testDuplicateImportMergesAnnotationWithoutReplacingLogs() async throws {
        let roots = try makeRoots()
        defer { roots.cleanup() }
        let source = SessionStore(rootDirectory: roots.source)
        let target = SessionStore(rootDirectory: roots.target)
        let session = try await createFinalizedSession(
            store: source,
            note: "协作方注释",
            labels: ["remote"]
        )
        let firstExport = try await source.export(
            sessionID: session.id,
            scope: .wholeSession,
            destinationDirectory: roots.export
        )
        _ = try await target.importSession(from: firstExport)
        try await target.updateAnnotation(
            SessionAnnotation(
                title: "本地标题",
                note: "本地复核",
                labels: ["local"],
                updatedAt: Date()
            ),
            sessionID: session.id
        )
        try await source.updateAnnotation(
            SessionAnnotation(
                title: "协作标题",
                note: "补充复现步骤",
                labels: ["remote", "repro"],
                updatedAt: Date().addingTimeInterval(1)
            ),
            sessionID: session.id
        )
        let secondExport = try await source.export(
            sessionID: session.id,
            scope: .wholeSession,
            destinationDirectory: roots.export
        )

        let result = try await target.importSession(from: secondExport)
        let annotation = try await target.annotation(sessionID: session.id)
        let events = try await target.load(sessionID: session.id).2

        XCTAssertEqual(result.disposition, .mergedAnnotation)
        XCTAssertTrue(annotation.note.contains("本地复核"))
        XCTAssertTrue(annotation.note.contains("补充复现步骤"))
        XCTAssertEqual(annotation.labels, ["local", "remote", "repro"])
        XCTAssertEqual(events.count, 2)
    }

    func testImportRejectsTamperedLogsUsingManifestDigest() async throws {
        let roots = try makeRoots()
        defer { roots.cleanup() }
        let source = SessionStore(rootDirectory: roots.source)
        let target = SessionStore(rootDirectory: roots.target)
        let session = try await createFinalizedSession(store: source)
        let exported = try await source.export(
            sessionID: session.id,
            scope: .wholeSession,
            destinationDirectory: roots.export
        )
        let logsURL = exported.appending(path: "logs.jsonl")
        let original = try String(contentsOf: logsURL, encoding: .utf8)
        try original.replacingOccurrences(of: "event-1", with: "event-x")
            .write(to: logsURL, atomically: true, encoding: .utf8)

        do {
            _ = try await target.importSession(from: exported)
            XCTFail("Expected digest mismatch")
        } catch SessionStoreError.importDigestMismatch {
            // Expected.
        }
    }

    func testImportRejectsSymlinkedArtifact() async throws {
        let roots = try makeRoots()
        defer { roots.cleanup() }
        let source = SessionStore(rootDirectory: roots.source)
        let target = SessionStore(rootDirectory: roots.target)
        let (session, paths) = try await createSession(store: source)
        let screenshot = paths.screenshotsDirectory.appending(path: "shot.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: screenshot)
        try await source.append(
            artifact: CaptureEvidence(
                kind: .screenshot,
                fileURL: screenshot,
                deviceSerial: "serial"
            ),
            sessionID: session.id
        )
        _ = try await source.finalize(sessionID: session.id)
        let exported = try await source.export(
            sessionID: session.id,
            scope: .wholeSession,
            destinationDirectory: roots.export
        )
        let exportedShot = exported.appending(path: "screenshots/shot.png")
        try FileManager.default.removeItem(at: exportedShot)
        try FileManager.default.createSymbolicLink(
            at: exportedShot,
            withDestinationURL: URL(fileURLWithPath: "/etc/hosts")
        )

        do {
            _ = try await target.importSession(from: exported)
            XCTFail("Expected unsafe import rejection")
        } catch SessionStoreError.unsafeImportPackage {
            // Expected.
        }
    }

    func testImportRejectsSymlinkedSessionRoot() async throws {
        let roots = try makeRoots()
        defer { roots.cleanup() }
        let source = SessionStore(rootDirectory: roots.source)
        let target = SessionStore(rootDirectory: roots.target)
        let session = try await createFinalizedSession(store: source)
        let exported = try await source.export(
            sessionID: session.id,
            scope: .wholeSession,
            destinationDirectory: roots.export
        )
        let linkedRoot = roots.base.appending(
            path: "linked-session",
            directoryHint: .isDirectory
        )
        try FileManager.default.createSymbolicLink(
            at: linkedRoot,
            withDestinationURL: exported
        )

        do {
            _ = try await target.importSession(from: linkedRoot)
            XCTFail("Expected symlinked root rejection")
        } catch SessionStoreError.unsafeImportPackage {
            // Expected.
        }
    }

    func testImportRejectsOversizedJSONMetadata() async throws {
        let roots = try makeRoots()
        defer { roots.cleanup() }
        let source = SessionStore(rootDirectory: roots.source)
        let target = SessionStore(rootDirectory: roots.target)
        let session = try await createFinalizedSession(store: source)
        let exported = try await source.export(
            sessionID: session.id,
            scope: .wholeSession,
            destinationDirectory: roots.export
        )
        try FileManager.default.removeItem(
            at: exported.appending(path: "collaboration-manifest.json")
        )
        try Data(repeating: 0x20, count: 16 * 1_024 * 1_024 + 1).write(
            to: exported.appending(path: "annotation.json")
        )

        do {
            _ = try await target.importSession(from: exported)
            XCTFail("Expected oversized metadata rejection")
        } catch SessionStoreError.unsafeImportPackage {
            // Expected.
        }
    }

    func testPersistsRegressionBaselineAndSymbolicationReport() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GameLogP2Store-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(rootDirectory: root)
        let session = try await createFinalizedSession(store: store)
        let baseline = try await store.setRegressionBaseline(sessionID: session.id)
        let report = SessionSymbolicationReport(
            sessionID: session.id,
            symbolizerPath: "/ndk/llvm-symbolizer",
            catalogRevision: Date(),
            frames: []
        )
        try await store.saveSymbolicationReport(report, sessionID: session.id)
        let reopened = SessionStore(rootDirectory: root)
        let reopenedBaselines = try await reopened.regressionBaselines()
        let reopenedReport = try await reopened.symbolicationReport(
            sessionID: session.id
        )

        XCTAssertEqual(reopenedBaselines.map(\.sessionID), [baseline.sessionID])
        XCTAssertEqual(
            reopenedBaselines.map(\.targetPackage),
            [baseline.targetPackage]
        )
        XCTAssertEqual(
            reopenedBaselines.first?.updatedAt.timeIntervalSince1970 ?? 0,
            baseline.updatedAt.timeIntervalSince1970,
            accuracy: 1
        )
        XCTAssertEqual(reopenedReport?.id, report.id)
        XCTAssertEqual(reopenedReport?.sessionID, report.sessionID)
        XCTAssertEqual(reopenedReport?.symbolizerPath, report.symbolizerPath)
        XCTAssertEqual(reopenedReport?.frames, report.frames)
    }

    func testPersistsNormalizedRegressionConfigurationPerPackage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(
                path: "GameLogRegressionConfig-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(rootDirectory: root)
        var configuration = RegressionConfiguration.recommended(
            for: "com.example.game"
        )
        configuration.thresholds.errorAbsoluteIncrease = -10
        configuration.thresholds.tagRelativeIncrease = 2.5
        configuration.ignoredAlertKeys = ["error-count", "tag.Unity"]

        let saved = try await store.updateRegressionConfiguration(configuration)
        let reopened = try await SessionStore(
            rootDirectory: root
        ).regressionConfigurations()

        XCTAssertEqual(saved.thresholds.errorAbsoluteIncrease, 1)
        XCTAssertEqual(reopened.count, 1)
        XCTAssertEqual(reopened.first?.thresholds.tagRelativeIncrease, 2.5)
        XCTAssertEqual(
            reopened.first?.ignoredAlertKeys,
            Set(["error-count", "tag.Unity"])
        )
    }

    private func createFinalizedSession(
        store: SessionStore,
        note: String = "",
        labels: [String] = []
    ) async throws -> DebugSession {
        let (session, _) = try await createSession(store: store)
        try await store.append(
            events: [makeEvent(1), makeEvent(2)],
            sessionID: session.id
        )
        _ = try await store.finalize(sessionID: session.id)
        if !note.isEmpty || !labels.isEmpty {
            try await store.updateAnnotation(
                SessionAnnotation(
                    title: "共享会话",
                    note: note,
                    labels: labels,
                    updatedAt: Date()
                ),
                sessionID: session.id
            )
        }
        return session
    }

    private func createSession(
        store: SessionStore
    ) async throws -> (DebugSession, SessionPaths) {
        try await store.create(
            device: AndroidDevice(
                serial: "serial",
                state: .online,
                model: "Test Device",
                product: nil,
                transportID: nil
            ),
            targetPackage: "com.example.game",
            pids: [42],
            adbPath: "/tmp/adb",
            adbVersion: "1.0.41",
            initialPreset: .all
        )
    }

    private func makeEvent(_ index: Int) -> LogEvent {
        LogEvent(
            timestampText: "12:00:00.000",
            pid: 42,
            tid: 42,
            level: .info,
            tag: "Game",
            message: "event-\(index)",
            rawText: "event-\(index)",
            buffer: .main
        )
    }

    private func makeRoots() throws -> TestRoots {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "GameLogP2-\(UUID().uuidString)", directoryHint: .isDirectory)
        let roots = TestRoots(
            base: base,
            source: base.appending(path: "source", directoryHint: .isDirectory),
            target: base.appending(path: "target", directoryHint: .isDirectory),
            export: base.appending(path: "export", directoryHint: .isDirectory)
        )
        try FileManager.default.createDirectory(
            at: roots.export,
            withIntermediateDirectories: true
        )
        return roots
    }
}

private struct TestRoots {
    let base: URL
    let source: URL
    let target: URL
    let export: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: base)
    }
}
