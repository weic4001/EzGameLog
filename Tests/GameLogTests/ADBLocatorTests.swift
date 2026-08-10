import Foundation
import XCTest
@testable import GameLog

final class ADBLocatorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "GameLog-ADBLocatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testUserSelectedADBOverridesBundledADB() async throws {
        let selected = try makeFakeADB(name: "selected-adb", version: "selected")
        let bundled = try makeFakeADB(name: "bundled-adb", version: "bundled")

        let installation = await ADBLocator().locate(
            savedPath: selected.path,
            bundledURL: bundled,
            environment: [:],
            homeDirectory: temporaryDirectory
        )

        XCTAssertEqual(installation?.executableURL.path, selected.path)
        XCTAssertEqual(installation?.source, .userSelected)
        XCTAssertEqual(installation?.versionText, "Android Debug Bridge selected")
    }

    func testBundledADBIsPreferredOverEnvironmentADB() async throws {
        let bundled = try makeFakeADB(name: "bundled-adb", version: "bundled")
        let environmentDirectory = temporaryDirectory.appending(
            path: "environment",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: environmentDirectory,
            withIntermediateDirectories: true
        )
        _ = try makeFakeADB(
            at: environmentDirectory.appending(path: "adb"),
            version: "environment"
        )

        let installation = await ADBLocator().locate(
            savedPath: nil,
            bundledURL: bundled,
            environment: ["PATH": environmentDirectory.path],
            homeDirectory: temporaryDirectory
        )

        XCTAssertEqual(installation?.executableURL.path, bundled.path)
        XCTAssertEqual(installation?.source, .bundled)
        XCTAssertEqual(installation?.versionText, "Android Debug Bridge bundled")
    }

    func testInvalidUserSelectionFallsBackToBundledADB() async throws {
        let bundled = try makeFakeADB(name: "bundled-adb", version: "bundled")

        let installation = await ADBLocator().locate(
            savedPath: temporaryDirectory.appending(path: "missing-adb").path,
            bundledURL: bundled,
            environment: [:],
            homeDirectory: temporaryDirectory
        )

        XCTAssertEqual(installation?.executableURL.path, bundled.path)
        XCTAssertEqual(installation?.source, .bundled)
    }

    private func makeFakeADB(name: String, version: String) throws -> URL {
        try makeFakeADB(at: temporaryDirectory.appending(path: name), version: version)
    }

    private func makeFakeADB(at url: URL, version: String) throws -> URL {
        try """
        #!/bin/sh
        printf '%s\\n' 'Android Debug Bridge \(version)'
        """.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }
}
