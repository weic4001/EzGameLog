import Foundation
import XCTest
@testable import GameLog

final class SessionStoreTests: XCTestCase {
    func testPersistsAndRemovesRecoverableRecordingAfterFinalization() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GameLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(rootDirectory: root)
        let device = makeDevice()
        let (session, _) = try await store.create(
            device: device,
            targetPackage: "com.example.game",
            pids: [42],
            adbPath: "/tmp/adb",
            adbVersion: "adb 1.0.41",
            initialPreset: .all
        )
        let pending = RecoverableRecording(
            deviceSerial: device.serial,
            remotePath: "/sdcard/gamelog-pending.mp4",
            localFileName: "Recording-pending.mp4",
            reason: "device disconnected"
        )

        try await store.append(recoverableRecording: pending, sessionID: session.id)
        let pendingBeforeFinalize = try await store.recoverableRecordings(sessionID: session.id)
        XCTAssertEqual(pendingBeforeFinalize.map(\.id), [pending.id])
        XCTAssertEqual(pendingBeforeFinalize.map(\.remotePath), [pending.remotePath])
        _ = try await store.finalize(sessionID: session.id)

        try await store.removeRecoverableRecording(id: pending.id, sessionID: session.id)
        let pendingAfterRemoval = try await store.recoverableRecordings(sessionID: session.id)
        XCTAssertEqual(pendingAfterRemoval, [])

        let marker = LogEvent(
            timestampText: "12:00:00.000",
            pid: 42,
            tid: nil,
            level: .info,
            tag: "GameLog",
            message: "recording recovered",
            rawText: "recording recovered",
            isMarker: true
        )
        try await store.append(events: [marker], sessionID: session.id)
        let (_, _, events, _) = try await store.load(sessionID: session.id)
        XCTAssertEqual(events.last?.id, marker.id)
        XCTAssertEqual(events.last?.message, marker.message)
    }

    func testPersistsRecoversAndFinalizesSession() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "GameLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let store = SessionStore(rootDirectory: temporaryRoot)
        var initialFilter = LogFilterConfiguration()
        initialFilter.enabledLevels = [.warning, .error, .fatal]
        initialFilter.includedTags = "Game"
        initialFilter.query = "timeout"

        let (session, _) = try await store.create(
            device: makeDevice(),
            targetPackage: "com.example.game",
            pids: [1234],
            adbPath: "/tmp/adb",
            adbVersion: "Android Debug Bridge 1.0.41",
            initialPreset: .all,
            initialFilterConfiguration: initialFilter
        )
        let events = [makeEvent(1), makeEvent(2)]
        try await store.append(events: events, sessionID: session.id)
        try await store.flush(sessionID: session.id)

        let recoverable = try await store.recoverableSessions()
        XCTAssertEqual(recoverable.map(\.id), [session.id])

        let loaded = try await store.load(sessionID: session.id)
        XCTAssertEqual(loaded.2.map(\.message), ["event-1", "event-2"])
        XCTAssertEqual(loaded.0.initialFilterConfiguration, initialFilter)
        let retainedTail = try await store.load(
            sessionID: session.id,
            retainingLast: 1
        )
        XCTAssertEqual(retainedTail.2.map(\.message), ["event-2"])

        let finalized = try await store.finalize(sessionID: session.id)
        XCTAssertNotNil(finalized.endedAt)
        let remainingRecoverable = try await store.recoverableSessions()
        XCTAssertTrue(remainingRecoverable.isEmpty)
    }

    func testExportsAtomicDirectoryWithStructuredAndPlainLogs() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "GameLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let exportRoot = FileManager.default.temporaryDirectory
            .appending(path: "GameLogExports-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
            try? FileManager.default.removeItem(at: exportRoot)
        }
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let store = SessionStore(rootDirectory: temporaryRoot)
        let (session, paths) = try await store.create(
            device: makeDevice(),
            targetPackage: "com.example.game",
            pids: [1234],
            adbPath: "/tmp/adb",
            adbVersion: "Android Debug Bridge 1.0.41",
            initialPreset: .warnings
        )
        let events = [makeEvent(1), makeEvent(2), makeEvent(3)]
        try await store.append(events: events, sessionID: session.id)
        let screenshotURL = paths.screenshotsDirectory.appending(path: "shot.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: screenshotURL)
        try await store.append(
            artifact: CaptureEvidence(
                kind: .screenshot,
                fileURL: screenshotURL,
                deviceSerial: "serial-1"
            ),
            sessionID: session.id
        )
        try await store.updateAnnotation(
            SessionAnnotation(
                title: "分享标题",
                note: "供协作者查看",
                labels: ["shared"],
                updatedAt: Date()
            ),
            sessionID: session.id
        )

        let exported = try await store.export(
            sessionID: session.id,
            scope: .filtered(Array(events.suffix(2))),
            destinationDirectory: exportRoot
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appending(path: "session.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appending(path: "logs.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appending(path: "screenshots/shot.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appending(path: "annotation.json").path))
        let plainText = try String(contentsOf: exported.appending(path: "logs.txt"), encoding: .utf8)
        XCTAssertEqual(plainText, "event-2\nevent-3\n")
        let partials = try FileManager.default.contentsOfDirectory(atPath: exportRoot.path)
            .filter { $0.hasPrefix(".GameLog-export-") }
        XCTAssertTrue(partials.isEmpty)

        let wholeExport = try await store.export(
            sessionID: session.id,
            scope: .wholeSession,
            destinationDirectory: exportRoot
        )
        let wholeText = try String(
            contentsOf: wholeExport.appending(path: "logs.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(wholeText, "event-1\nevent-2\nevent-3\n")
        XCTAssertEqual(
            try Data(contentsOf: wholeExport.appending(path: "logs.jsonl")),
            try Data(contentsOf: paths.jsonLinesLog)
        )
    }

    func testPersistsIncidentAndExportsRedactedProblemPackage() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "GameLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let exportRoot = FileManager.default.temporaryDirectory
            .appending(path: "GameLogExports-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
            try? FileManager.default.removeItem(at: exportRoot)
        }
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let store = SessionStore(rootDirectory: temporaryRoot)
        let (session, paths) = try await store.create(
            device: makeDevice(),
            targetPackage: "com.example.game",
            pids: [1234],
            adbPath: "/tmp/adb",
            adbVersion: "Android Debug Bridge 1.0.41",
            initialPreset: .all
        )
        let occurredAt = Date()
        let marker = LogEvent(
            occurredAt: occurredAt,
            timestampText: "12:00:00.000",
            pid: 1234,
            tid: nil,
            level: .info,
            tag: "GameLog",
            message: "问题标记",
            rawText: "问题标记",
            kind: .incident
        )
        let sensitive = LogEvent(
            occurredAt: occurredAt,
            timestampText: "12:00:00.100",
            pid: 1234,
            tid: 1235,
            level: .error,
            tag: "Auth",
            message: "Bearer abcdefghijklmnop",
            rawText: "Bearer abcdefghijklmnop",
            buffer: .main
        )
        try await store.append(events: [marker, sensitive], sessionID: session.id)
        let screenshotURL = paths.screenshotsDirectory.appending(path: "issue.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: screenshotURL)
        let screenshot = CaptureEvidence(
            kind: .screenshot,
            fileURL: screenshotURL,
            createdAt: occurredAt,
            deviceSerial: "serial-1"
        )
        try await store.append(artifact: screenshot, sessionID: session.id)
        let incident = IncidentRecord(
            createdAt: occurredAt,
            eventID: marker.id,
            title: "登录失败",
            note: "account_id=player_123",
            evidenceIDs: [screenshot.id]
        )
        try await store.upsert(incident: incident, sessionID: session.id)

        let storedIncidents = try await store.incidents(sessionID: session.id)
        XCTAssertEqual(storedIncidents.map(\.id), [incident.id])
        XCTAssertEqual(storedIncidents.map(\.eventID), [incident.eventID])
        XCTAssertEqual(storedIncidents.map(\.title), [incident.title])
        let exported = try await store.exportIncident(
            sessionID: session.id,
            incidentID: incident.id,
            destinationDirectory: exportRoot
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: exported.appending(path: "incident.json").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: exported.appending(path: "screenshots/issue.png").path
            )
        )
        let logs = try String(
            contentsOf: exported.appending(path: "logs.txt"),
            encoding: .utf8
        )
        XCTAssertFalse(logs.contains("abcdefghijklmnop"))
        let incidentJSON = try String(
            contentsOf: exported.appending(path: "incident.json"),
            encoding: .utf8
        )
        XCTAssertFalse(incidentJSON.contains("player_123"))
    }

    func testArchivesAnalyzesAndAnnotatesFinalizedSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GameLogArchiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(rootDirectory: root)
        let (session, _) = try await store.create(
            device: makeDevice(),
            targetPackage: "com.example.game",
            pids: [1234],
            adbPath: "/tmp/adb",
            adbVersion: "adb 1.0.41",
            initialPreset: .all
        )
        let crash = LogEvent(
            timestampText: "12:00:00.000",
            pid: 1234,
            tid: 1234,
            level: .fatal,
            tag: "AndroidRuntime",
            message: "FATAL EXCEPTION: main",
            rawText: "FATAL EXCEPTION: main",
            buffer: .crash
        )
        try await store.append(
            events: [makeEvent(1), crash],
            sessionID: session.id
        )
        _ = try await store.finalize(sessionID: session.id)
        try await store.updateAnnotation(
            SessionAnnotation(
                title: "登录回归",
                note: "复测账号切换",
                labels: ["release", "login", "release"],
                updatedAt: Date()
            ),
            sessionID: session.id
        )

        let entries = try await store.archiveEntries()
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.annotation.title, "登录回归")
        XCTAssertEqual(entry.annotation.labels, ["login", "release"])
        XCTAssertFalse(entry.isInProgress)

        let snapshot = try await store.analysis(sessionID: session.id)
        XCTAssertEqual(snapshot.logEventCount, 2)
        XCTAssertEqual(snapshot.diagnosticIssues.first?.kind, .javaCrash)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: entry.directoryURL.appending(path: "analysis.json").path
            )
        )
    }

    func testSharedStoreRejectsRootChangeWhileSessionIsActive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GameLogRootTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let otherRoot = FileManager.default.temporaryDirectory
            .appending(path: "GameLogOtherRoot-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: otherRoot)
        }
        let store = SessionStore(rootDirectory: root)
        _ = try await store.create(
            device: makeDevice(),
            targetPackage: "com.example.game",
            pids: [1234],
            adbPath: "/tmp/adb",
            adbVersion: "adb 1.0.41",
            initialPreset: .all
        )

        do {
            try await store.updateRootDirectory(otherRoot)
            XCTFail("Expected active session protection")
        } catch SessionStoreError.activeSessionsPreventDirectoryChange {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeDevice() -> AndroidDevice {
        AndroidDevice(
            serial: "serial-1",
            state: .online,
            model: "Test Device",
            product: "test",
            transportID: "1"
        )
    }

    private func makeEvent(_ index: Int) -> LogEvent {
        LogEvent(
            timestampText: "07-23 11:00:00.000",
            pid: 1234,
            tid: 1235,
            level: .info,
            tag: "Test",
            message: "event-\(index)",
            rawText: "event-\(index)",
            buffer: .main
        )
    }
}
