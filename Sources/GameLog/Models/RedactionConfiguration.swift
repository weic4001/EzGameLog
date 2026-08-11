import Foundation

enum RedactionCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case accessToken
    case accountIdentifier
    case emailAddress
    case ipAddress
    case deviceSerial
    case localPath

    var title: String {
        switch self {
        case .accessToken: String(localized: "Token / 密钥")
        case .accountIdentifier: String(localized: "账号标识")
        case .emailAddress: String(localized: "邮箱地址")
        case .ipAddress: String(localized: "IP 地址")
        case .deviceSerial: String(localized: "设备序列号")
        case .localPath: String(localized: "本地路径")
        }
    }
}

struct CustomRedactionRule: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var name: String
    var pattern: String
    var replacement: String
    var packagePattern: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        pattern: String,
        replacement: String = String(localized: "‹已脱敏:自定义规则›"),
        packagePattern: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.replacement = replacement
        self.packagePattern = packagePattern
        self.isEnabled = isEnabled
    }

    func applies(to targetPackage: String) -> Bool {
        let scope = packagePattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scope.isEmpty else { return true }
        if scope.hasSuffix(".*") {
            return targetPackage.hasPrefix(String(scope.dropLast()))
        }
        return targetPackage == scope
    }
}

struct RedactionConfiguration: Equatable, Codable, Sendable {
    var isEnabled: Bool
    var categories: Set<RedactionCategory>
    var customRules: [CustomRedactionRule]

    init(
        isEnabled: Bool,
        categories: Set<RedactionCategory>,
        customRules: [CustomRedactionRule] = []
    ) {
        self.isEnabled = isEnabled
        self.categories = categories
        self.customRules = customRules
    }

    static let recommended = RedactionConfiguration(
        isEnabled: true,
        categories: Set(RedactionCategory.allCases)
    )

    static let disabled = RedactionConfiguration(
        isEnabled: false,
        categories: []
    )
}

struct RedactionPreview: Equatable, Sendable {
    let counts: [RedactionCategory: Int]
    let customRuleCounts: [UUID: Int]
    let sampleBefore: String?
    let sampleAfter: String?

    var totalMatchCount: Int {
        counts.values.reduce(0, +) + customRuleCounts.values.reduce(0, +)
    }
}

enum PendingExportKind: Sendable {
    case session(SessionExportScope)
    case incident(UUID)
}

struct ExportPreviewState: Identifiable, Sendable {
    let id: UUID
    let kind: PendingExportKind
    let preview: RedactionPreview
    var configuration: RedactionConfiguration

    init(
        kind: PendingExportKind,
        preview: RedactionPreview,
        configuration: RedactionConfiguration = .recommended
    ) {
        id = UUID()
        self.kind = kind
        self.preview = preview
        self.configuration = configuration
    }
}
