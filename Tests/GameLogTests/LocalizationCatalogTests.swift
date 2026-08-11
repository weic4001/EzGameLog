import Foundation
import XCTest
@testable import GameLog

final class LocalizationCatalogTests: XCTestCase {
    func testCatalogHasCompleteEnglishCoverage() throws {
        let catalog = try loadCatalog()

        XCTAssertEqual(catalog.sourceLanguage, "zh-Hans")
        XCTAssertGreaterThanOrEqual(catalog.strings.count, 698)

        let missingEnglish = catalog.strings.compactMap { key, entry in
            entry.localizations?["en"]?.stringUnit?.value == nil ? key : nil
        }
        XCTAssertEqual(missingEnglish, [], "Missing English translations: \(missingEnglish)")
    }

    func testEnglishTranslationsPreserveFormatPlaceholders() throws {
        let catalog = try loadCatalog()
        let mismatches = catalog.strings.compactMap { key, entry -> String? in
            guard let english = entry.localizations?["en"]?.stringUnit?.value else {
                return key
            }
            return placeholders(in: key) == placeholders(in: english) ? nil : key
        }

        XCTAssertEqual(mismatches, [], "Placeholder mismatches: \(mismatches)")
    }

    func testRepresentativeEnglishCopy() throws {
        let catalog = try loadCatalog()

        XCTAssertEqual(englishValue(for: "设备", in: catalog), "Device")
        XCTAssertEqual(englishValue(for: "开始录屏", in: catalog), "Start Recording")
        XCTAssertEqual(englishValue(for: "搜索 Tag 或消息", in: catalog), "Search Tags or Messages")
        XCTAssertEqual(englishValue(for: "会话归档与对比", in: catalog), "Session Archive & Comparison")
    }

    private func englishValue(for key: String, in catalog: Catalog) -> String? {
        catalog.strings[key]?.localizations?["en"]?.stringUnit?.value
    }

    private func placeholders(in value: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|d|@)"#)
        let range = NSRange(value.startIndex..., in: value)
        return pattern.matches(in: value, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: value) else { return nil }
            return value[swiftRange].replacingOccurrences(
                of: #"^%\d+\$"#,
                with: "%",
                options: .regularExpression
            )
        }.sorted()
    }

    private func loadCatalog() throws -> Catalog {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = repositoryRoot
            .appending(path: "Sources/GameLog/Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
    }
}

private struct Catalog: Decodable {
    let sourceLanguage: String
    let strings: [String: CatalogEntry]
}

private struct CatalogEntry: Decodable {
    let localizations: [String: CatalogLocalization]?
}

private struct CatalogLocalization: Decodable {
    let stringUnit: CatalogStringUnit?
}

private struct CatalogStringUnit: Decodable {
    let value: String
}
