import Foundation

enum ADBInstallationSource: String, Sendable, Equatable {
    case bundled
    case userSelected
    case environment
    case commonLocation

    var title: String {
        switch self {
        case .bundled:
            String(localized: "内置 ADB")
        case .userSelected:
            String(localized: "外部 ADB")
        case .environment:
            String(localized: "环境中的 ADB")
        case .commonLocation:
            String(localized: "常用位置中的 ADB")
        }
    }
}

struct ADBInstallation: Sendable {
    let executableURL: URL
    let versionText: String
    let source: ADBInstallationSource
}

struct ADBLocator: Sendable {
    func locate(savedPath: String?) async -> ADBInstallation? {
        await locate(
            savedPath: savedPath,
            bundledURL: Bundle.main.url(forAuxiliaryExecutable: "adb"),
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    func locate(
        savedPath: String?,
        bundledURL: URL?,
        environment: [String: String],
        homeDirectory: URL
    ) async -> ADBInstallation? {
        for candidate in candidates(
            savedPath: savedPath,
            bundledURL: bundledURL,
            environment: environment,
            homeDirectory: homeDirectory
        ) {
            guard FileManager.default.isExecutableFile(atPath: candidate.url.path) else { continue }
            let executor = ADBExecutor(executableURL: candidate.url)
            guard let result = try? await executor.run(
                ["version"],
                timeout: .seconds(5)
            ) else { continue }
            let version = result.stdoutText
                .split(separator: "\n")
                .first
                .map(String.init) ?? "Android Debug Bridge"
            return ADBInstallation(
                executableURL: candidate.url,
                versionText: version,
                source: candidate.source
            )
        }
        return nil
    }

    private struct Candidate {
        let url: URL
        let source: ADBInstallationSource
    }

    private func candidates(
        savedPath: String?,
        bundledURL: URL?,
        environment: [String: String],
        homeDirectory: URL
    ) -> [Candidate] {
        var candidates: [(String, ADBInstallationSource)] = []

        if let savedPath, !savedPath.isEmpty {
            candidates.append((savedPath, .userSelected))
        }
        if let bundledURL {
            candidates.append((bundledURL.path, .bundled))
        }
        if let environmentPath = environment["PATH"] {
            candidates.append(contentsOf: environmentPath
                .split(separator: ":")
                .map { (String($0) + "/adb", .environment) })
        }
        for variable in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = environment[variable], !root.isEmpty {
                candidates.append((root + "/platform-tools/adb", .environment))
            }
        }
        candidates.append(contentsOf: [
            (homeDirectory.appending(path: "Library/Android/sdk/platform-tools/adb").path, .commonLocation),
            (homeDirectory.appending(path: "DevelopSdk/android/platform-tools/adb").path, .commonLocation),
            ("/opt/homebrew/bin/adb", .commonLocation),
            ("/usr/local/bin/adb", .commonLocation)
        ])

        var seen = Set<String>()
        return candidates.compactMap { path, source in
            var isDirectory: ObjCBool = false
            let expanded = NSString(string: path).expandingTildeInPath
            let resolved: String
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                resolved = URL(fileURLWithPath: expanded).appending(path: "adb").path
            } else {
                resolved = expanded
            }
            guard seen.insert(resolved).inserted else { return nil }
            return Candidate(
                url: URL(fileURLWithPath: resolved),
                source: source
            )
        }
    }
}
