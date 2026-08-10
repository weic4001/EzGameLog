import Foundation
import XCTest
@testable import GameLog

final class NativeSymbolicationServiceTests: XCTestCase {
    func testParsesAndSymbolicatesNativeFrameByBuildID() async throws {
        let issue = makeNativeIssue(
            """
            signal 11 (SIGSEGV)
            #00 pc 0000000000012abc /data/app/lib/arm64/libgame.so (GameLoop+0x18) (BuildId: A1B2C3)
            """
        )
        let root = SymbolCatalogRoot(
            path: "/symbols",
            packagePattern: "com.example.game"
        )
        let record = SymbolFileRecord(
            rootID: root.id,
            path: "/symbols/arm64-v8a/libgame.so",
            libraryName: "libgame.so",
            abi: .arm64,
            buildID: "a1b2c3",
            byteCount: 4_096,
            modifiedAt: nil
        )
        let catalog = SymbolCatalog(
            roots: [root],
            files: [record],
            symbolizerPath: "/tmp/llvm-symbolizer",
            revisedAt: Date(timeIntervalSince1970: 100)
        )

        let report = try await NativeSymbolicationService.symbolicate(
            sessionID: UUID(),
            targetPackage: "com.example.game",
            issues: [issue],
            catalog: catalog,
            symbolizerURL: URL(fileURLWithPath: "/tmp/llvm-symbolizer"),
            executor: FakeSymbolizer(
                output: "Game::Tick()\n/source/Game.cpp:42:7\n"
            )
        )

        let frame = try XCTUnwrap(report.frames.first)
        XCTAssertEqual(frame.frame.address, "0000000000012abc")
        XCTAssertEqual(frame.frame.abi, .arm64)
        XCTAssertEqual(frame.status, .symbolicated)
        XCTAssertEqual(frame.sourceFrames.first?.function, "Game::Tick()")
        XCTAssertEqual(frame.sourceFrames.first?.file, "/source/Game.cpp")
        XCTAssertEqual(frame.sourceFrames.first?.line, 42)
        XCTAssertEqual(frame.sourceFrames.first?.column, 7)
    }

    func testDoesNotGuessBetweenAmbiguousSymbolFiles() async throws {
        let issue = makeNativeIssue(
            "#00 pc 00000010 /data/app/libgame.so"
        )
        let root = SymbolCatalogRoot(path: "/symbols", packagePattern: "")
        let records = ["/symbols/a/libgame.so", "/symbols/b/libgame.so"].map {
            SymbolFileRecord(
                rootID: root.id,
                path: $0,
                libraryName: "libgame.so",
                abi: .unknown,
                buildID: nil,
                byteCount: 1,
                modifiedAt: nil
            )
        }
        let catalog = SymbolCatalog(
            roots: [root],
            files: records,
            symbolizerPath: "/tmp/llvm-symbolizer",
            revisedAt: Date()
        )

        let report = try await NativeSymbolicationService.symbolicate(
            sessionID: UUID(),
            targetPackage: "com.example.game",
            issues: [issue],
            catalog: catalog,
            symbolizerURL: URL(fileURLWithPath: "/tmp/llvm-symbolizer"),
            executor: FakeSymbolizer(output: "should not be called")
        )

        XCTAssertEqual(report.frames.first?.status, .missingSymbolFile)
        XCTAssertTrue(report.frames.first?.errorMessage?.contains("2 个同名库") == true)
    }

    func testReadsELFBuildIDAndArchitecture() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GameLogELF-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "libgame.so")
        try makeELF64(machine: 183, buildID: [0x01, 0x23, 0x45, 0x67]).write(to: file)

        let metadata = try ELFMetadataReader.read(from: file)

        XCTAssertEqual(metadata.abi, .arm64)
        XCTAssertEqual(metadata.buildID, "01234567")
    }

    func testIndexesELFFilesWithProjectScope() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GameLogSymbols-\(UUID().uuidString)", directoryHint: .isDirectory)
        let catalogRoot = FileManager.default.temporaryDirectory
            .appending(path: "GameLogCatalog-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: catalogRoot)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeELF64(machine: 62, buildID: [0xAA, 0xBB]).write(
            to: root.appending(path: "libengine.so")
        )
        try Data("not elf".utf8).write(to: root.appending(path: "libinvalid.so"))
        let store = SymbolCatalogStore(rootDirectory: catalogRoot)

        let indexedRoot = try await store.index(
            directory: root,
            packagePattern: "com.example.*"
        )
        let catalog = try await store.catalog()

        XCTAssertEqual(indexedRoot.packagePattern, "com.example.*")
        XCTAssertEqual(catalog.files.count, 1)
        XCTAssertEqual(catalog.files.first?.abi, .x86_64)
        XCTAssertEqual(catalog.files.first?.buildID, "aabb")
    }

    func testReportExplainsCoverageMissingLibrariesAndPlainText() {
        let diagnosticID = UUID()
        let resolvedFrame = NativeStackFrame(
            diagnosticID: diagnosticID,
            frameIndex: 0,
            address: "10",
            libraryPath: "/data/libgame.so",
            libraryName: "libgame.so",
            rawLine: "#00 pc 10 /data/libgame.so"
        )
        let missingFrame = NativeStackFrame(
            diagnosticID: diagnosticID,
            frameIndex: 1,
            address: "20",
            libraryPath: "/data/libmissing.so",
            libraryName: "libmissing.so",
            rawLine: "#01 pc 20 /data/libmissing.so"
        )
        let report = SessionSymbolicationReport(
            sessionID: UUID(),
            symbolizerPath: "/ndk/llvm-symbolizer",
            catalogRevision: Date(),
            frames: [
                SymbolicatedNativeFrame(
                    frame: resolvedFrame,
                    status: .symbolicated,
                    symbolFilePath: "/symbols/libgame.so",
                    sourceFrames: [
                        SymbolizedSourceFrame(
                            function: "Game::Tick()",
                            file: "/source/Game.cpp",
                            line: 42,
                            column: 7
                        )
                    ],
                    errorMessage: nil
                ),
                SymbolicatedNativeFrame(
                    frame: missingFrame,
                    status: .missingSymbolFile,
                    symbolFilePath: nil,
                    sourceFrames: [],
                    errorMessage: "缺少 libmissing.so 的匹配符号文件。"
                )
            ]
        )

        XCTAssertEqual(report.symbolicatedCount, 1)
        XCTAssertEqual(report.coverageRatio, 0.5, accuracy: 0.001)
        XCTAssertEqual(report.count(for: .missingSymbolFile), 1)
        XCTAssertEqual(report.missingLibraryNames, ["libmissing.so"])
        XCTAssertTrue(report.plainText.contains("Game::Tick()"))
        XCTAssertTrue(report.plainText.contains("Reason: 缺少 libmissing.so"))
    }

    private func makeNativeIssue(_ summary: String) -> DiagnosticIssue {
        DiagnosticIssue(
            id: UUID(),
            kind: .nativeCrash,
            signature: "native:libgame",
            title: "Native crash",
            summary: summary,
            firstOccurredAt: Date(),
            lastOccurredAt: Date(),
            occurrenceCount: 1,
            eventIDs: [UUID()]
        )
    }

    private func makeELF64(machine: UInt16, buildID: [UInt8]) -> Data {
        var data = Data(repeating: 0, count: 256)
        data[0] = 0x7F
        data[1] = 0x45
        data[2] = 0x4C
        data[3] = 0x46
        data[4] = 2 // ELF64
        data[5] = 1 // little endian
        write(machine, to: &data, at: 18)
        write(UInt64(64), to: &data, at: 32)
        write(UInt16(56), to: &data, at: 54)
        write(UInt16(1), to: &data, at: 56)
        write(UInt32(4), to: &data, at: 64) // PT_NOTE
        write(UInt64(128), to: &data, at: 72)
        let paddedDescription = (buildID.count + 3) & ~3
        write(UInt64(16 + paddedDescription), to: &data, at: 96)
        write(UInt32(4), to: &data, at: 128)
        write(UInt32(buildID.count), to: &data, at: 132)
        write(UInt32(3), to: &data, at: 136)
        data.replaceSubrange(140..<144, with: [0x47, 0x4E, 0x55, 0x00])
        data.replaceSubrange(144..<144 + buildID.count, with: buildID)
        return data
    }

    private func write<T: FixedWidthInteger>(
        _ value: T,
        to data: inout Data,
        at offset: Int
    ) {
        for index in 0..<MemoryLayout<T>.size {
            data[offset + index] = UInt8(
                truncatingIfNeeded: value >> T(index * 8)
            )
        }
    }
}

private struct FakeSymbolizer: SymbolizerExecuting {
    let output: String

    func symbolize(
        executableURL: URL,
        objectURL: URL,
        address: String
    ) async throws -> String {
        output
    }
}
