import XCTest
@testable import GameLog

final class IOSDeviceServiceTests: XCTestCase {
    func testListsIOSDeviceWithMetadataAndProcesses() async throws {
        let fake = FakeIOSDeviceExecutor { tool, arguments in
            switch (tool, arguments) {
            case (.deviceID, ["--list"]):
                return FakeIOSDeviceExecutor.result("00008120-TEST\n")
            case (.deviceInfo, ["--udid", "00008120-TEST", "--xml"]):
                return FakeIOSDeviceExecutor.result(Self.deviceInfoXML)
            case (.deviceSyslog, ["--udid", "00008120-TEST", "pidlist"]):
                return FakeIOSDeviceExecutor.result("1 launchd\n42 ExampleGame\n43 ExampleGame\n")
            default:
                XCTFail("Unexpected command: \(tool.rawValue) \(arguments)")
                return FakeIOSDeviceExecutor.result("")
            }
        }
        let service = IOSDeviceService(executor: fake)

        let devices = try await service.listDevices()
        let device = try XCTUnwrap(devices.first)
        XCTAssertEqual(device.platform, .iOS)
        XCTAssertEqual(device.displayName, "Test iPhone")
        XCTAssertEqual(device.product, "iPhone15,2")
        XCTAssertEqual(device.operatingSystemVersion, "26.5.2")
        XCTAssertEqual(device.connectionType, .usb)

        let processes = try await service.listProcesses(serial: device.serial)
        XCTAssertEqual(processes.map(\.name), ["ExampleGame", "ExampleGame", "launchd"])
        let pids = try await service.pids(forProcess: "ExampleGame", serial: device.serial)
        XCTAssertEqual(pids, [42, 43])
    }

    func testRejectsProcessFilterSeparator() async {
        let fake = FakeIOSDeviceExecutor { tool, arguments in
            XCTFail("Invalid process reached \(tool.rawValue): \(arguments)")
            return FakeIOSDeviceExecutor.result("")
        }
        do {
            _ = try await IOSDeviceService(executor: fake).pids(
                forProcess: "Game|SpringBoard",
                serial: "00008120-TEST"
            )
            XCTFail("Expected invalid process name")
        } catch IOSDeviceServiceError.invalidProcessName {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLegacyDeviceMetadataDefaultsToAndroidPlatform() throws {
        let data = Data(#"{"serial":"usb-1","state":"device","model":"Pixel","product":null,"transportID":null,"androidVersion":"16","apiLevel":36,"connectionType":"USB"}"#.utf8)
        let device = try JSONDecoder().decode(AndroidDevice.self, from: data)
        XCTAssertEqual(device.platform, .android)
    }

    private static let deviceInfoXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>DeviceName</key><string>Test iPhone</string>
    <key>ProductType</key><string>iPhone15,2</string>
    <key>ProductVersion</key><string>26.5.2</string>
    </dict></plist>
    """
}
