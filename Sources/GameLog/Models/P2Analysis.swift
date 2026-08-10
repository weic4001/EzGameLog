import Foundation

enum NativeABI: String, Codable, CaseIterable, Sendable {
    case arm64 = "arm64-v8a"
    case arm = "armeabi-v7a"
    case x86_64
    case x86
    case unknown

    var title: String {
        switch self {
        case .arm64: "ARM64"
        case .arm: "ARMv7"
        case .x86_64: "x86_64"
        case .x86: "x86"
        case .unknown: "未知架构"
        }
    }
}

struct NativeStackFrame: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let diagnosticID: UUID
    let frameIndex: Int
    let address: String
    let libraryPath: String
    let libraryName: String
    let existingSymbol: String?
    let buildID: String?
    let abi: NativeABI
    let rawLine: String

    init(
        id: UUID = UUID(),
        diagnosticID: UUID,
        frameIndex: Int,
        address: String,
        libraryPath: String,
        libraryName: String,
        existingSymbol: String? = nil,
        buildID: String? = nil,
        abi: NativeABI = .unknown,
        rawLine: String
    ) {
        self.id = id
        self.diagnosticID = diagnosticID
        self.frameIndex = frameIndex
        self.address = address
        self.libraryPath = libraryPath
        self.libraryName = libraryName
        self.existingSymbol = existingSymbol
        self.buildID = buildID
        self.abi = abi
        self.rawLine = rawLine
    }
}

struct SymbolizedSourceFrame: Hashable, Codable, Sendable {
    let function: String
    let file: String?
    let line: Int?
    let column: Int?
}

enum SymbolicationFrameStatus: String, Codable, CaseIterable, Sendable {
    case symbolicated
    case alreadySymbolicated
    case missingSymbolFile
    case unresolved
    case failed

    var title: String {
        switch self {
        case .symbolicated: "已符号化"
        case .alreadySymbolicated: "日志已有符号"
        case .missingSymbolFile: "缺少符号文件"
        case .unresolved: "未解析"
        case .failed: "解析失败"
        }
    }
}

struct SymbolicatedNativeFrame: Identifiable, Hashable, Codable, Sendable {
    let frame: NativeStackFrame
    let status: SymbolicationFrameStatus
    let symbolFilePath: String?
    let sourceFrames: [SymbolizedSourceFrame]
    let errorMessage: String?

    var id: UUID { frame.id }
    var bestFunction: String? {
        sourceFrames.first?.function ?? frame.existingSymbol
    }
}

struct SessionSymbolicationReport: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let sessionID: UUID
    let generatedAt: Date
    let symbolizerPath: String
    let catalogRevision: Date
    let frames: [SymbolicatedNativeFrame]

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        generatedAt: Date = Date(),
        symbolizerPath: String,
        catalogRevision: Date,
        frames: [SymbolicatedNativeFrame]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.generatedAt = generatedAt
        self.symbolizerPath = symbolizerPath
        self.catalogRevision = catalogRevision
        self.frames = frames
    }

    var symbolicatedCount: Int {
        frames.filter {
            $0.status == .symbolicated || $0.status == .alreadySymbolicated
        }.count
    }

    var coverageRatio: Double {
        guard !frames.isEmpty else { return 0 }
        return Double(symbolicatedCount) / Double(frames.count)
    }

    func count(for status: SymbolicationFrameStatus) -> Int {
        frames.lazy.filter { $0.status == status }.count
    }

    var missingLibraryNames: [String] {
        Array(Set(frames.compactMap { value in
            value.status == .missingSymbolFile
                ? value.frame.libraryName
                : nil
        }))
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var plainText: String {
        var lines = [
            "GameLog Native Symbolication",
            "Session: \(sessionID.uuidString)",
            "Generated: \(generatedAt.formatted(.iso8601))",
            "Symbolizer: \(symbolizerPath)",
            "Coverage: \(symbolicatedCount)/\(frames.count) "
                + "(\(coverageRatio.formatted(.percent.precision(.fractionLength(1)))))",
            ""
        ]
        for value in frames {
            lines.append(value.frame.rawLine)
            lines.append("  Status: \(value.status.title)")
            if let path = value.symbolFilePath {
                lines.append("  Symbol file: \(path)")
            }
            for source in value.sourceFrames {
                let location = source.file.map { file in
                    source.line.map { "\(file):\($0)" } ?? file
                }
                lines.append(
                    "  \(source.function)"
                        + (location.map { " — \($0)" } ?? "")
                )
            }
            if let error = value.errorMessage {
                lines.append("  Reason: \(error)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

struct SymbolCatalogRoot: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let path: String
    let packagePattern: String
    let addedAt: Date

    init(
        id: UUID = UUID(),
        path: String,
        packagePattern: String,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.packagePattern = packagePattern
        self.addedAt = addedAt
    }
}

struct SymbolFileRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let rootID: UUID
    let path: String
    let libraryName: String
    let abi: NativeABI
    let buildID: String?
    let byteCount: Int64
    let modifiedAt: Date?

    init(
        id: UUID = UUID(),
        rootID: UUID,
        path: String,
        libraryName: String,
        abi: NativeABI,
        buildID: String?,
        byteCount: Int64,
        modifiedAt: Date?
    ) {
        self.id = id
        self.rootID = rootID
        self.path = path
        self.libraryName = libraryName
        self.abi = abi
        self.buildID = buildID
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
    }
}

struct SymbolCatalog: Hashable, Codable, Sendable {
    var roots: [SymbolCatalogRoot]
    var files: [SymbolFileRecord]
    var symbolizerPath: String
    var revisedAt: Date

    static let empty = SymbolCatalog(
        roots: [],
        files: [],
        symbolizerPath: "",
        revisedAt: .distantPast
    )

    func roots(for package: String) -> [SymbolCatalogRoot] {
        roots.filter {
            $0.packagePattern.isEmpty
                || $0.packagePattern == package
                || ($0.packagePattern.hasSuffix(".*")
                    && package.hasPrefix(String($0.packagePattern.dropLast())))
        }
    }

    func files(for package: String) -> [SymbolFileRecord] {
        let rootIDs = Set(roots(for: package).map(\.id))
        return files.filter { rootIDs.contains($0.rootID) }
    }
}

enum TimelineAlignmentMethod: String, Codable, Sendable {
    case matchingEvent
    case matchingDiagnostic
    case sessionStart

    var title: String {
        switch self {
        case .matchingEvent: "共同日志锚点"
        case .matchingDiagnostic: "共同诊断锚点"
        case .sessionStart: "会话开始时间"
        }
    }
}

struct TimelineAnchor: Hashable, Codable, Sendable {
    let title: String
    let baselineEventID: UUID?
    let comparisonEventID: UUID?
    let baselineTime: Date
    let comparisonTime: Date
}

struct SessionTimelineAlignment: Hashable, Codable, Sendable {
    let baselineSessionID: UUID
    let comparisonSessionID: UUID
    let method: TimelineAlignmentMethod
    let comparisonOffset: TimeInterval
    let confidence: Double
    let anchor: TimelineAnchor

    func alignedComparisonTime(_ time: Date) -> Date {
        time.addingTimeInterval(comparisonOffset)
    }
}

enum RegressionSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case critical

    var title: String {
        switch self {
        case .info: "提示"
        case .warning: "警告"
        case .critical: "严重"
        }
    }
}

struct RegressionAlert: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let severity: RegressionSeverity
    let title: String
    let detail: String
    let metric: String
    let baselineValue: Int?
    let comparisonValue: Int?

    var suppressionKey: String { metric }

    init(
        id: UUID = UUID(),
        severity: RegressionSeverity,
        title: String,
        detail: String,
        metric: String,
        baselineValue: Int? = nil,
        comparisonValue: Int? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.metric = metric
        self.baselineValue = baselineValue
        self.comparisonValue = comparisonValue
    }
}

struct RegressionReport: Hashable, Codable, Sendable {
    let baselineSessionID: UUID
    let comparisonSessionID: UUID
    let generatedAt: Date
    let alerts: [RegressionAlert]
    let suppressedAlertCount: Int

    init(
        baselineSessionID: UUID,
        comparisonSessionID: UUID,
        generatedAt: Date,
        alerts: [RegressionAlert],
        suppressedAlertCount: Int = 0
    ) {
        self.baselineSessionID = baselineSessionID
        self.comparisonSessionID = comparisonSessionID
        self.generatedAt = generatedAt
        self.alerts = alerts
        self.suppressedAlertCount = suppressedAlertCount
    }

    var highestSeverity: RegressionSeverity? {
        alerts.max { lhs, rhs in
            Self.rank(lhs.severity) < Self.rank(rhs.severity)
        }?.severity
    }

    private static func rank(_ severity: RegressionSeverity) -> Int {
        switch severity {
        case .info: 0
        case .warning: 1
        case .critical: 2
        }
    }
}

struct RegressionBaseline: Hashable, Codable, Sendable {
    let targetPackage: String
    let sessionID: UUID
    let updatedAt: Date
}

struct SessionCollaborationManifest: Hashable, Codable, Sendable {
    let formatVersion: Int
    let generatedAt: Date
    let appVersion: String
    let exportScope: String
    let sessionID: UUID
    let sessionSHA256: String
    let logsSHA256: String
    let annotationSHA256: String?
}

enum SessionImportDisposition: String, Codable, Sendable {
    case imported
    case mergedAnnotation
}

struct SessionImportResult: Hashable, Codable, Sendable {
    let sessionID: UUID
    let targetPackage: String
    let disposition: SessionImportDisposition
    let importedEventCount: Int
    let mergedLabelCount: Int
}
