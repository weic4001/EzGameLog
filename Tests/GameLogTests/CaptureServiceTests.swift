import Foundation
import XCTest
@testable import GameLog

final class CaptureServiceTests: XCTestCase {
    func testNativeRecordingContinuesUntilCancelledThenPullsAndRemovesRemote() async throws {
        let calls = RecordingCommandLog()
        let fake = FakeADBExecutor { arguments, serial in
            await calls.append(arguments)
            XCTAssertEqual(serial, "usb-1")
            if arguments.prefix(2) == ["shell", "screenrecord"] {
                try await Task.sleep(for: .seconds(30))
            }
            if arguments.first == "pull", let destination = arguments.last {
                try Data("mock-mp4-payload".utf8).write(
                    to: URL(fileURLWithPath: destination),
                    options: .atomic
                )
            }
            return FakeADBExecutor.result("")
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GameLogRecordingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recordingTask = Task {
            try await CaptureService(executor: fake).recordScreen(
                serial: "usb-1",
                destinationDirectory: directory
            )
        }
        for _ in 0..<100 {
            let didStart = await calls.values.contains {
                $0.prefix(2) == ["shell", "screenrecord"]
            }
            if didStart { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let didStartRecording = await calls.values.contains {
            $0.prefix(2) == ["shell", "screenrecord"]
        }
        XCTAssertTrue(didStartRecording)
        recordingTask.cancel()
        let evidence = try await recordingTask.value
        let recordedCalls = await calls.values

        XCTAssertEqual(evidence.kind, .recording)
        XCTAssertTrue(FileManager.default.fileExists(atPath: evidence.fileURL.path))
        XCTAssertEqual(recordedCalls.first, ["shell", "test", "-w", "/sdcard"])
        XCTAssertTrue(recordedCalls.contains {
            $0.prefix(2) == ["shell", "screenrecord"]
                && $0.contains("--time-limit")
                && $0.contains("180")
        })
        XCTAssertTrue(recordedCalls.contains { $0.first == "pull" })
        XCTAssertTrue(recordedCalls.contains { $0.prefix(2) == ["shell", "rm"] })
    }

    func testNativeRecordingContinuesWithAnotherSegmentAndMergesOnStop() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GameLogSegmentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let sampleURL = directory.appending(path: "sample.mp4")
        try await ScreenshotVideoEncoder.encode(
            frames: [
                CapturedVideoFrame(pngData: png, presentationTime: 0),
                CapturedVideoFrame(pngData: png, presentationTime: 0.1)
            ],
            outputURL: sampleURL
        )
        let sampleData = try Data(contentsOf: sampleURL)
        try FileManager.default.removeItem(at: sampleURL)

        let calls = RecordingCommandLog()
        let fake = FakeADBExecutor { arguments, _ in
            await calls.append(arguments)
            if arguments.prefix(2) == ["shell", "screenrecord"],
               await calls.screenrecordCount > 1 {
                try await Task.sleep(for: .seconds(30))
            }
            if arguments.first == "pull", let destination = arguments.last {
                try sampleData.write(
                    to: URL(fileURLWithPath: destination),
                    options: .atomic
                )
            }
            return FakeADBExecutor.result("")
        }

        let recordingTask = Task {
            try await CaptureService(executor: fake).recordScreen(
                serial: "usb-1",
                destinationDirectory: directory
            )
        }
        for _ in 0..<100 {
            if await calls.screenrecordCount > 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let segmentCountBeforeStop = await calls.screenrecordCount
        XCTAssertGreaterThan(segmentCountBeforeStop, 1)

        recordingTask.cancel()
        let evidence = try await recordingTask.value
        let metadata = await MediaMetadataReader.video(at: evidence.fileURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: evidence.fileURL.path))
        XCTAssertGreaterThan(metadata.duration ?? 0, 0.1)
    }

    func testRecoveryRejectsTamperedPathsBeforeInvokingADB() async {
        let fake = FakeADBExecutor { arguments, _ in
            XCTFail("Tampered recovery metadata reached ADB: \(arguments)")
            return FakeADBExecutor.result("")
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GameLogRecoveryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try await CaptureService(executor: fake).recoverRecording(
                serial: "usb-1",
                remotePath: "/sdcard/gamelog-safe.mp4;rm -rf /sdcard",
                localFileName: "../outside.mp4",
                destinationDirectory: directory
            )
            XCTFail("Expected invalid recovery metadata")
        } catch CaptureError.invalidRecoveryMetadata {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testScreenshotValidatesPNGAndPersistsMetadata() async throws {
        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let fake = FakeADBExecutor { arguments, serial in
            XCTAssertEqual(arguments, ["exec-out", "screencap", "-p"])
            XCTAssertEqual(serial, "usb-1")
            return ADBCommandResult(stdout: png, stderr: Data(), exitCode: 0)
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GameLogCaptureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let evidence = try await CaptureService(executor: fake).takeScreenshot(
            serial: "usb-1",
            destinationDirectory: directory
        )

        XCTAssertEqual(evidence.kind, .screenshot)
        XCTAssertEqual(evidence.pixelWidth, 1)
        XCTAssertEqual(evidence.pixelHeight, 1)
        XCTAssertNotNil(evidence.byteCount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: evidence.fileURL.path))
        XCTAssertTrue(
            evidence.thumbnailURL.map {
                FileManager.default.fileExists(atPath: $0.path)
            } ?? false
        )
    }

    func testScreenshotRejectsNonPNGOutput() async throws {
        let fake = FakeADBExecutor { _, _ in
            ADBCommandResult(stdout: Data("permission denied".utf8), stderr: Data(), exitCode: 0)
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GameLogCaptureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try await CaptureService(executor: fake).takeScreenshot(
                serial: "usb-1",
                destinationDirectory: directory
            )
            XCTFail("Expected invalid screenshot")
        } catch CaptureError.invalidScreenshot {
            // Expected.
        }
    }
}

private actor RecordingCommandLog {
    private(set) var values: [[String]] = []

    var screenrecordCount: Int {
        values.count { $0.prefix(2) == ["shell", "screenrecord"] }
    }

    func append(_ value: [String]) {
        values.append(value)
    }
}
