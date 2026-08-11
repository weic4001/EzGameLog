import Foundation

actor SymbolCatalogStore {
    private let catalogURL: URL
    private var cachedCatalog: SymbolCatalog?

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(
                    path: "Library/Application Support/GameLog/Symbols",
                    directoryHint: .isDirectory
                )
        catalogURL = root.appending(path: "catalog.json")
    }

    func catalog() throws -> SymbolCatalog {
        if let cachedCatalog {
            return cachedCatalog
        }
        guard FileManager.default.fileExists(atPath: catalogURL.path) else {
            cachedCatalog = .empty
            return .empty
        }
        let value = try Self.decoder.decode(
            SymbolCatalog.self,
            from: Data(contentsOf: catalogURL)
        )
        cachedCatalog = value
        return value
    }

    func index(
        directory: URL,
        packagePattern: String
    ) throws -> SymbolCatalogRoot {
        let normalizedPattern = packagePattern.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard Self.isValidPackagePattern(normalizedPattern) else {
            throw SymbolCatalogError.invalidPackagePattern
        }
        let resolvedDirectory = directory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: resolvedDirectory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw SymbolCatalogError.directoryNotFound
        }

        var value = try catalog()
        let root = value.roots.first {
            $0.path == resolvedDirectory.path
                && $0.packagePattern == normalizedPattern
        } ?? SymbolCatalogRoot(
            path: resolvedDirectory.path,
            packagePattern: normalizedPattern
        )
        let records = try Self.scan(directory: resolvedDirectory, rootID: root.id)
        if records.isEmpty {
            throw SymbolCatalogError.noELFFiles
        }
        value.roots.removeAll { $0.id == root.id }
        value.roots.append(root)
        value.roots.sort {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        value.files.removeAll { $0.rootID == root.id }
        value.files.append(contentsOf: records)
        value.files.sort {
            if $0.libraryName == $1.libraryName {
                return $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
            return $0.libraryName.localizedStandardCompare($1.libraryName)
                == .orderedAscending
        }
        value.revisedAt = Date()
        try persist(value)
        return root
    }

    func removeRoot(id: UUID) throws {
        var value = try catalog()
        value.roots.removeAll { $0.id == id }
        value.files.removeAll { $0.rootID == id }
        value.revisedAt = Date()
        try persist(value)
    }

    func setSymbolizerPath(_ path: String) throws {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty || FileManager.default.isExecutableFile(atPath: normalized) else {
            throw SymbolCatalogError.symbolizerNotExecutable
        }
        var value = try catalog()
        value.symbolizerPath = normalized
        value.revisedAt = Date()
        try persist(value)
    }

    func resolvedSymbolizerURL() throws -> URL? {
        let value = try catalog()
        if !value.symbolizerPath.isEmpty,
           FileManager.default.isExecutableFile(atPath: value.symbolizerPath) {
            return URL(fileURLWithPath: value.symbolizerPath)
        }
        return NDKSymbolizerLocator.locate()
    }

    private func persist(_ catalog: SymbolCatalog) throws {
        try FileManager.default.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.encoder.encode(catalog).write(to: catalogURL, options: .atomic)
        cachedCatalog = catalog
    }

    private static func scan(
        directory: URL,
        rootID: UUID
    ) throws -> [SymbolFileRecord] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw SymbolCatalogError.directoryNotFound
        }

        var records: [SymbolFileRecord] = []
        for case let url as URL in enumerator {
            if records.count >= 50_000 {
                throw SymbolCatalogError.tooManyFiles
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true,
                  values?.isSymbolicLink != true,
                  url.lastPathComponent.contains(".so") else {
                continue
            }
            guard let metadata = try? ELFMetadataReader.read(from: url) else {
                continue
            }
            records.append(SymbolFileRecord(
                rootID: rootID,
                path: url.standardizedFileURL.path,
                libraryName: url.lastPathComponent,
                abi: metadata.abi,
                buildID: metadata.buildID,
                byteCount: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate
            ))
        }
        return records
    }

    private static func isValidPackagePattern(_ value: String) -> Bool {
        if value.isEmpty { return true }
        if value.hasSuffix(".*") {
            return AndroidPackageName.isValid(String(value.dropLast(2)))
        }
        return AndroidPackageName.isValid(value)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum NDKSymbolizerLocator {
    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let manager = FileManager.default
        var candidates: [URL] = []
        for key in ["ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"] {
            if let root = environment[key], !root.isEmpty {
                candidates.append(contentsOf: toolchainCandidates(root: URL(fileURLWithPath: root)))
            }
        }
        if let androidHome = environment["ANDROID_HOME"], !androidHome.isEmpty {
            let ndkRoot = URL(fileURLWithPath: androidHome)
                .appending(path: "ndk", directoryHint: .isDirectory)
            if let versions = try? manager.contentsOfDirectory(
                at: ndkRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for version in versions.sorted(by: {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                        == .orderedDescending
                }) {
                    candidates.append(contentsOf: toolchainCandidates(root: version))
                }
            }
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/llvm-symbolizer"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/llvm-symbolizer"))
        return candidates.first { manager.isExecutableFile(atPath: $0.path) }
    }

    private static func toolchainCandidates(root: URL) -> [URL] {
        [
            root.appending(path: "toolchains/llvm/prebuilt/darwin-arm64/bin/llvm-symbolizer"),
            root.appending(path: "toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-symbolizer")
        ]
    }
}

enum SymbolCatalogError: LocalizedError, Sendable {
    case invalidPackagePattern
    case directoryNotFound
    case noELFFiles
    case tooManyFiles
    case symbolizerNotExecutable

    var errorDescription: String? {
        switch self {
        case .invalidPackagePattern:
            String(localized: "项目范围必须留空、使用完整包名或形如 com.example.*。")
        case .directoryNotFound:
            String(localized: "找不到所选符号目录。")
        case .noELFFiles:
            String(localized: "目录中没有可识别的 ELF .so 文件。")
        case .tooManyFiles:
            String(localized: "符号目录超过 50,000 个库文件，请缩小目录范围。")
        case .symbolizerNotExecutable:
            String(localized: "所选 llvm-symbolizer 不可执行。")
        }
    }
}
