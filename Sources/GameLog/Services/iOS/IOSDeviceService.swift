import Foundation

struct IOSDeviceService: Sendable {
    let executor: any IOSDeviceExecuting
    private let metadataCache = IOSDeviceMetadataCache()

    func listDevices() async throws -> [AndroidDevice] {
        let result = try await executor.run(
            .deviceID,
            arguments: ["--list"],
            timeout: .seconds(10)
        )
        let identifiers = result.stdoutText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        return await withTaskGroup(of: AndroidDevice.self) { group in
            for identifier in identifiers {
                group.addTask { await device(identifier: identifier) }
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
        let result = try await executor.run(
            .deviceSyslog,
            arguments: ["--udid", serial, "pidlist"],
            timeout: .seconds(15)
        )
        var seen = Set<Int>()
        return result.stdoutText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> AndroidProcess? in
                let fields = line.split(
                    maxSplits: 1,
                    whereSeparator: { $0 == " " || $0 == "\t" }
                )
                guard fields.count == 2,
                      let pid = Int(fields[0]),
                      pid > 0,
                      seen.insert(pid).inserted else {
                    return nil
                }
                let name = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard IOSProcessName.isValid(name) else { return nil }
                return AndroidProcess(pid: pid, name: name)
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    func pids(forProcess processName: String, serial: String) async throws -> Set<Int> {
        guard IOSProcessName.isValid(processName) else {
            throw IOSDeviceServiceError.invalidProcessName
        }
        return Set(
            try await listProcesses(serial: serial)
                .filter { $0.name == processName }
                .map(\.pid)
        )
    }

    private func device(identifier: String) async -> AndroidDevice {
        if let cached = await metadataCache.value(for: identifier) {
            return cached
        }
        do {
            let result = try await executor.run(
                .deviceInfo,
                arguments: ["--udid", identifier, "--xml"],
                timeout: .seconds(10)
            )
            guard let values = try PropertyListSerialization.propertyList(
                from: result.stdout,
                options: [],
                format: nil
            ) as? [String: Any] else {
                throw IOSDeviceServiceError.invalidDeviceInformation
            }
            let device = AndroidDevice(
                platform: .iOS,
                serial: identifier,
                state: .online,
                model: values["DeviceName"] as? String,
                product: values["ProductType"] as? String,
                transportID: nil,
                androidVersion: values["ProductVersion"] as? String,
                apiLevel: nil,
                connectionType: .usb
            )
            await metadataCache.store(device, for: identifier)
            return device
        } catch {
            let state = await pairingState(identifier: identifier)
            return AndroidDevice(
                platform: .iOS,
                serial: identifier,
                state: state,
                model: nil,
                product: nil,
                transportID: nil,
                connectionType: .usb
            )
        }
    }

    private func pairingState(identifier: String) async -> DeviceConnectionState {
        do {
            _ = try await executor.run(
                .devicePair,
                arguments: ["--udid", identifier, "validate"],
                timeout: .seconds(5)
            )
            return .offline
        } catch {
            return .unauthorized
        }
    }
}

enum IOSDeviceServiceError: LocalizedError, Sendable {
    case invalidProcessName
    case invalidDeviceInformation

    var errorDescription: String? {
        switch self {
        case .invalidProcessName:
            String(localized: "iOS 进程名无效。")
        case .invalidDeviceInformation:
            String(localized: "无法解析 iOS 设备信息。")
        }
    }
}

enum IOSProcessName {
    static func isValid(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= 255,
              !normalized.contains("|"),
              !normalized.contains("\0") else {
            return false
        }
        return true
    }
}

private actor IOSDeviceMetadataCache {
    private var values: [String: AndroidDevice] = [:]

    func value(for identifier: String) -> AndroidDevice? {
        values[identifier]
    }

    func store(_ device: AndroidDevice, for identifier: String) {
        values[identifier] = device
    }
}
