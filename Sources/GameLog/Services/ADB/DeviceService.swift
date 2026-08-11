import Foundation

struct DeviceService: Sendable {
    let executor: any ADBExecuting
    private let metadataCache = DeviceMetadataCache()

    func listDevices() async throws -> [AndroidDevice] {
        let result = try await executor.run(["devices", "-l"], timeout: .seconds(10))
        let parsed = result.stdoutText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
            .compactMap(parseDevice)
        return await withTaskGroup(of: AndroidDevice.self) { group in
            for device in parsed {
                group.addTask {
                    guard device.state == .online else { return device }
                    return await enriched(device)
                }
            }
            var devices: [AndroidDevice] = []
            for await device in group {
                devices.append(device)
            }
            return devices.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        }
    }

    func listProcesses(serial: String) async throws -> [AndroidProcess] {
        let result: ADBCommandResult
        do {
            result = try await executor.run(
                ["shell", "ps", "-A", "-o", "PID,NAME"],
                serial: serial,
                timeout: .seconds(10)
            )
        } catch {
            result = try await executor.run(
                ["shell", "ps", "-A"],
                serial: serial,
                timeout: .seconds(10)
            )
        }

        var seen = Set<Int>()
        return result.stdoutText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> AndroidProcess? in
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count >= 2 else { return nil }

                if let pid = Int(fields[0]) {
                    let name = String(fields.last!)
                    guard seen.insert(pid).inserted else { return nil }
                    return AndroidProcess(pid: pid, name: name)
                }

                guard fields.count >= 9, let pid = Int(fields[1]) else { return nil }
                let name = String(fields.last!)
                guard seen.insert(pid).inserted else { return nil }
                return AndroidProcess(pid: pid, name: name)
            }
            .filter { AndroidPackageName.isValid($0.name) }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func pids(forPackage packageName: String, serial: String) async throws -> Set<Int> {
        guard AndroidPackageName.isValid(packageName) else {
            throw DeviceServiceError.invalidPackageName
        }
        if let result = try? await executor.run(
            ["shell", "pidof", packageName],
            serial: serial,
            timeout: .seconds(5)
        ) {
            let pids = Set(result.stdoutText
                .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                .compactMap { Int($0) })
            if !pids.isEmpty {
                return pids
            }
        }
        let processes = try await listProcesses(serial: serial)
        return Set(processes
            .filter { $0.name == packageName || $0.name.hasPrefix(packageName + ":") }
            .map(\.pid))
    }

    func availableStorageBytes(serial: String) async throws -> Int64? {
        let result = try await executor.run(
            ["shell", "df", "-k", "/data/local/tmp"],
            serial: serial,
            timeout: .seconds(5)
        )
        for line in result.stdoutText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .reversed() {
            let numericFields = line
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .dropFirst()
                .compactMap { Int64($0) }
            guard numericFields.count >= 3 else { continue }
            return numericFields[2] * 1_024
        }
        return nil
    }

    func pairWirelessDevice(
        host: String,
        port: Int,
        pairingCode: String
    ) async throws -> String {
        let endpoint = try WirelessADBEndpoint(host: host, port: port)
        let normalizedCode = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCode.range(of: #"^\d{6}$"#, options: .regularExpression) != nil else {
            throw DeviceServiceError.invalidPairingCode
        }
        let result = try await executor.run(
            ["pair", endpoint.address, normalizedCode],
            timeout: .seconds(30)
        )
        let response = combinedOutput(result)
        guard response.localizedCaseInsensitiveContains("successfully paired")
            || response.localizedCaseInsensitiveContains("already paired") else {
            throw DeviceServiceError.wirelessCommandFailed(
                response.isEmpty ? String(localized: "ADB 未返回配对结果。") : response
            )
        }
        return response
    }

    func connectWirelessDevice(host: String, port: Int) async throws -> String {
        let endpoint = try WirelessADBEndpoint(host: host, port: port)
        let result = try await executor.run(
            ["connect", endpoint.address],
            timeout: .seconds(20)
        )
        let response = combinedOutput(result)
        guard response.localizedCaseInsensitiveContains("connected to")
            || response.localizedCaseInsensitiveContains("already connected") else {
            throw DeviceServiceError.wirelessCommandFailed(
                response.isEmpty ? String(localized: "ADB 未返回连接结果。") : response
            )
        }
        return response
    }

    func disconnectWirelessDevice(host: String, port: Int) async throws -> String {
        let endpoint = try WirelessADBEndpoint(host: host, port: port)
        let result = try await executor.run(
            ["disconnect", endpoint.address],
            timeout: .seconds(10)
        )
        return combinedOutput(result)
    }

    private func parseDevice(_ line: Substring) -> AndroidDevice? {
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2 else { return nil }
        let serial = String(fields[0])
        let state = DeviceConnectionState(rawValue: String(fields[1])) ?? .unknown
        let attributePairs: [(String, String)] = fields.dropFirst(2).compactMap { field in
            let pair = field.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { return nil }
            return (String(pair[0]), String(pair[1]))
        }
        let attributes = Dictionary(uniqueKeysWithValues: attributePairs)
        return AndroidDevice(
            serial: serial,
            state: state,
            model: attributes["model"],
            product: attributes["product"],
            transportID: attributes["transport_id"]
        )
    }

    private func enriched(_ device: AndroidDevice) async -> AndroidDevice {
        if let cached = await metadataCache.value(for: device.serial) {
            return AndroidDevice(
                serial: device.serial,
                state: device.state,
                model: device.model,
                product: device.product,
                transportID: device.transportID,
                androidVersion: cached.version,
                apiLevel: cached.apiLevel,
                connectionType: device.connectionType
            )
        }
        async let versionResult = try? executor.run(
            ["shell", "getprop", "ro.build.version.release"],
            serial: device.serial,
            timeout: .seconds(5)
        )
        async let apiResult = try? executor.run(
            ["shell", "getprop", "ro.build.version.sdk"],
            serial: device.serial,
            timeout: .seconds(5)
        )
        let version = await versionResult?.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        let api = await apiResult.flatMap {
            Int($0.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        await metadataCache.store(
            DeviceMetadata(version: version?.isEmpty == false ? version : nil, apiLevel: api),
            for: device.serial
        )
        return AndroidDevice(
            serial: device.serial,
            state: device.state,
            model: device.model,
            product: device.product,
            transportID: device.transportID,
            androidVersion: version,
            apiLevel: api,
            connectionType: device.connectionType
        )
    }

    private func combinedOutput(_ result: ADBCommandResult) -> String {
        [result.stdoutText, result.stderrText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum DeviceServiceError: LocalizedError, Sendable {
    case invalidPackageName
    case invalidWirelessEndpoint
    case invalidPairingCode
    case wirelessCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPackageName:
            String(localized: "包名格式无效。请输入类似 com.example.game 的 Android 包名。")
        case .invalidWirelessEndpoint:
            String(localized: "无线 ADB 地址无效。请输入主机地址和 1–65535 端口。")
        case .invalidPairingCode:
            String(localized: "配对码应为 6 位数字。")
        case .wirelessCommandFailed(let message):
            message
        }
    }
}

struct WirelessADBEndpoint: Hashable, Sendable {
    let host: String
    let port: Int

    init(host: String, port: Int) throws {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: ".-:[]_%"))
        guard !normalizedHost.isEmpty,
              normalizedHost.unicodeScalars.allSatisfy(allowed.contains),
              (1...65_535).contains(port) else {
            throw DeviceServiceError.invalidWirelessEndpoint
        }
        self.host = normalizedHost
        self.port = port
    }

    var address: String {
        if host.contains(":"), !host.hasPrefix("[") {
            return "[\(host)]:\(port)"
        }
        return "\(host):\(port)"
    }
}

private struct DeviceMetadata: Sendable {
    let version: String?
    let apiLevel: Int?
}

private actor DeviceMetadataCache {
    private var values: [String: DeviceMetadata] = [:]

    func value(for serial: String) -> DeviceMetadata? {
        values[serial]
    }

    func store(_ metadata: DeviceMetadata, for serial: String) {
        values[serial] = metadata
    }
}
