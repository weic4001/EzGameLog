import Foundation

enum IOSDeviceToolSource: String, Sendable {
    case bundled
    case homebrew

    var title: String {
        switch self {
        case .bundled: String(localized: "App 内置")
        case .homebrew: "Homebrew"
        }
    }
}

struct IOSDeviceToolInstallation: Sendable {
    let toolURLs: [IOSDeviceTool: URL]
    let versionText: String
    let source: IOSDeviceToolSource
}

struct IOSDeviceToolLocator: Sendable {
    func locate() async -> IOSDeviceToolInstallation? {
        for candidate in candidates() {
            guard let toolURLs = toolURLs(in: candidate.directory) else { continue }
            let executor = IOSDeviceToolExecutor(toolURLs: toolURLs)
            guard let result = try? await executor.run(
                .deviceID,
                arguments: ["--version"],
                timeout: .seconds(5)
            ) else {
                continue
            }
            let version = [result.stdoutText, result.stderrText]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return IOSDeviceToolInstallation(
                toolURLs: toolURLs,
                versionText: version.isEmpty ? "libimobiledevice" : version,
                source: candidate.source
            )
        }
        return nil
    }

    private func toolURLs(in directory: URL) -> [IOSDeviceTool: URL]? {
        var result: [IOSDeviceTool: URL] = [:]
        for tool in IOSDeviceTool.allCases {
            let url = directory.appending(path: tool.rawValue)
            guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
            result[tool] = url
        }
        return result
    }

    private func candidates() -> [(directory: URL, source: IOSDeviceToolSource)] {
        var values: [(URL, IOSDeviceToolSource)] = []
        if let executable = Bundle.main.executableURL {
            values.append((executable.deletingLastPathComponent(), .bundled))
        }

        #if DEBUG
        let projectDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        values.append((
            projectDirectory.appending(path: "ThirdParty/iOSDeviceTools/bin", directoryHint: .isDirectory),
            .bundled
        ))
        values.append((
            URL(fileURLWithPath: "/opt/homebrew/opt/libimobiledevice/bin", isDirectory: true),
            .homebrew
        ))
        values.append((
            URL(fileURLWithPath: "/usr/local/opt/libimobiledevice/bin", isDirectory: true),
            .homebrew
        ))
        #endif

        var seen = Set<String>()
        return values.filter { seen.insert($0.0.standardizedFileURL.path).inserted }
    }
}
