import Foundation
import XCTest
@testable import GameLog

final class PerformanceBaselineTests: XCTestCase {
    func testWholeSessionExportStreamsOneHundredThousandEvents() async throws {
        let sessionRoot = FileManager.default.temporaryDirectory
            .appending(path: "GameLogLargeSession-\(UUID().uuidString)", directoryHint: .isDirectory)
        let exportRoot = FileManager.default.temporaryDirectory
            .appending(path: "GameLogLargeExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: sessionRoot)
            try? FileManager.default.removeItem(at: exportRoot)
        }
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let store = SessionStore(rootDirectory: sessionRoot)
        let (session, _) = try await store.create(
            device: AndroidDevice(
                serial: "stress-device",
                state: .online,
                model: "Stress Device",
                product: "stress",
                transportID: "1"
            ),
            targetPackage: "com.example.stress",
            pids: [42],
            adbPath: "/tmp/adb",
            adbVersion: "adb 1.0.41",
            initialPreset: .all
        )
        for batchStart in stride(from: 0, to: 100_000, by: 1_000) {
            let events = (batchStart..<(batchStart + 1_000)).map { index in
                LogEvent(
                    timestampText: "12:00:00.000",
                    pid: 42,
                    tid: 43,
                    level: .info,
                    tag: "Stress",
                    message: "event-\(index)",
                    rawText: "event-\(index)",
                    buffer: .main
                )
            }
            try await store.append(events: events, sessionID: session.id)
        }
        _ = try await store.finalize(sessionID: session.id)
        let clock = ContinuousClock()
        let startedAt = clock.now

        let exported = try await store.export(
            sessionID: session.id,
            scope: .wholeSession,
            destinationDirectory: exportRoot
        )
        let elapsed = startedAt.duration(to: clock.now)
        let textData = try Data(contentsOf: exported.appending(path: "logs.txt"))

        XCTAssertEqual(textData.reduce(into: 0) { count, byte in
            if byte == 0x0A { count += 1 }
        }, 100_000)
        XCTAssertGreaterThan(
            try exported.appending(path: "logs.jsonl")
                .resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0,
            1_000_000
        )
        XCTAssertLessThan(elapsed, .seconds(30))
    }

    func testBoundedPipelineProcessesSyntheticSustainedInput() throws {
        let requestedCount = ProcessInfo.processInfo.environment["GAMELOG_STRESS_EVENTS"]
            .flatMap(Int.init)
        let totalEventCount = max(100_000, requestedCount ?? 100_000)
        let capacity = 50_000
        let batchSize = 500
        var buffer = LogBuffer(capacity: capacity)
        var evicted = 0
        let clock = ContinuousClock()
        let startedAt = clock.now

        for batchStart in stride(from: 0, to: totalEventCount, by: batchSize) {
            let batchEnd = min(totalEventCount, batchStart + batchSize)
            let batch = (batchStart..<batchEnd).map { index in
                LogEvent(
                    timestampText: "12:00:00.000",
                    pid: index.isMultiple(of: 2) ? 42 : 7,
                    tid: 42,
                    level: index.isMultiple(of: 10) ? .error : .info,
                    tag: index.isMultiple(of: 10) ? "Game.Network" : "Game.Render",
                    message: index.isMultiple(of: 10)
                        ? "needle request failed \(index)"
                        : "frame rendered \(index)",
                    rawText: "raw \(index)",
                    buffer: .main
                )
            }
            evicted += buffer.append(contentsOf: batch)
        }

        var configuration = LogFilterConfiguration()
        configuration.pidScope = .all
        configuration.query = "needle"
        let filtered = try LogFilterEngine.filter(
            events: buffer.events,
            configuration: configuration,
            targetPIDs: []
        )
        let elapsed = startedAt.duration(to: clock.now)
        let allowedSeconds = max(12, (totalEventCount / 100_000) * 12)

        XCTAssertEqual(buffer.events.count, capacity)
        XCTAssertEqual(evicted, totalEventCount - capacity)
        XCTAssertEqual(filtered.count, capacity / 10)
        XCTAssertLessThan(
            elapsed,
            .seconds(allowedSeconds),
            "Synthetic pipeline took \(elapsed) for \(totalEventCount) events"
        )
    }

    func testParserHandlesFiveThousandLineBurst() {
        let input = (0..<5_000)
            .map {
                "2026-07-23 12:00:00.123 +0800 123 456 I Game: burst-\($0)\n"
            }
            .joined()
        var parser = LogcatParser()
        let clock = ContinuousClock()
        let startedAt = clock.now

        var events = parser.consume(Data(input.utf8))
        events.append(contentsOf: parser.finish())
        let elapsed = startedAt.duration(to: clock.now)

        XCTAssertEqual(events.count, 5_000)
        XCTAssertEqual(events.first?.message, "burst-0")
        XCTAssertEqual(events.last?.message, "burst-4999")
        XCTAssertLessThan(elapsed, .seconds(3))
    }
}
