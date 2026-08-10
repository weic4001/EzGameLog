import XCTest
@testable import GameLog

final class DeviceServiceTests: XCTestCase {
    func testParsesAvailableDeviceStorageFromDF() async throws {
        let executor = FakeADBExecutor { arguments, serial in
            XCTAssertEqual(serial, "serial-1")
            XCTAssertEqual(arguments, ["shell", "df", "-k", "/data/local/tmp"])
            return FakeADBExecutor.result(
                "Filesystem 1K-blocks Used Available Use% Mounted on\n/dev/block/dm-8 100000 25000 75000 25% /data\n"
            )
        }

        let bytes = try await DeviceService(executor: executor)
            .availableStorageBytes(serial: "serial-1")

        XCTAssertEqual(bytes, 75_000 * 1_024)
    }

    func testListsOnlineUnauthorizedAndOfflineDevicesWithMetadata() async throws {
        let fake = FakeADBExecutor { arguments, serial in
            switch arguments {
            case ["devices", "-l"]:
                return FakeADBExecutor.result("""
                List of devices attached
                usb-1 device product:test model:Pixel_9 transport_id:1
                usb-2 unauthorized transport_id:2
                192.168.0.2:5555 offline transport_id:3

                """)
            case ["shell", "getprop", "ro.build.version.release"]:
                XCTAssertEqual(serial, "usb-1")
                return FakeADBExecutor.result("16\n")
            case ["shell", "getprop", "ro.build.version.sdk"]:
                XCTAssertEqual(serial, "usb-1")
                return FakeADBExecutor.result("36\n")
            default:
                XCTFail("Unexpected command: \(arguments)")
                return FakeADBExecutor.result("")
            }
        }

        let devices = try await DeviceService(executor: fake).listDevices()

        XCTAssertEqual(devices.count, 3)
        let online = try XCTUnwrap(devices.first { $0.serial == "usb-1" })
        XCTAssertEqual(online.state, .online)
        XCTAssertEqual(online.androidVersion, "16")
        XCTAssertEqual(online.apiLevel, 36)
        XCTAssertEqual(online.connectionType, .usb)
        XCTAssertEqual(devices.first { $0.serial == "usb-2" }?.state, .unauthorized)
        XCTAssertEqual(
            devices.first { $0.serial == "192.168.0.2:5555" }?.connectionType,
            .wireless
        )
    }

    func testReturnsAllPackagePIDs() async throws {
        let fake = FakeADBExecutor { arguments, _ in
            XCTAssertEqual(arguments, ["shell", "pidof", "com.example.game"])
            return FakeADBExecutor.result("41 42 43\n")
        }

        let pids = try await DeviceService(executor: fake).pids(
            forPackage: "com.example.game",
            serial: "usb-1"
        )

        XCTAssertEqual(pids, [41, 42, 43])
    }

    func testRejectsUnsafePackageNameBeforeInvokingADB() async {
        let fake = FakeADBExecutor { arguments, _ in
            XCTFail("Unsafe package name reached ADB: \(arguments)")
            return FakeADBExecutor.result("")
        }

        do {
            _ = try await DeviceService(executor: fake).pids(
                forPackage: "com.example.game;rm -rf /sdcard",
                serial: "usb-1"
            )
            XCTFail("Expected invalid package name")
        } catch DeviceServiceError.invalidPackageName {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAndroidPackageValidationAllowsProcessSuffix() {
        XCTAssertTrue(AndroidPackageName.isValid("com.example.game"))
        XCTAssertTrue(AndroidPackageName.isValid("com.example.game:worker_1"))
        XCTAssertFalse(AndroidPackageName.isValid("game"))
        XCTAssertFalse(AndroidPackageName.isValid("com.example.game && id"))
    }

    func testPairsAndConnectsWirelessDeviceWithValidatedArguments() async throws {
        let fake = FakeADBExecutor { arguments, serial in
            XCTAssertNil(serial)
            switch arguments.first {
            case "pair":
                XCTAssertEqual(arguments, ["pair", "192.168.1.8:37123", "123456"])
                return FakeADBExecutor.result("Successfully paired to 192.168.1.8:37123\n")
            case "connect":
                XCTAssertEqual(arguments, ["connect", "192.168.1.8:38888"])
                return FakeADBExecutor.result("connected to 192.168.1.8:38888\n")
            default:
                XCTFail("Unexpected command: \(arguments)")
                return FakeADBExecutor.result("")
            }
        }
        let service = DeviceService(executor: fake)

        _ = try await service.pairWirelessDevice(
            host: "192.168.1.8",
            port: 37_123,
            pairingCode: "123456"
        )
        _ = try await service.connectWirelessDevice(
            host: "192.168.1.8",
            port: 38_888
        )
    }

    func testRejectsUnsafeWirelessEndpointAndPairingCodeBeforeADB() async {
        let fake = FakeADBExecutor { arguments, _ in
            XCTFail("Invalid wireless input reached ADB: \(arguments)")
            return FakeADBExecutor.result("")
        }
        let service = DeviceService(executor: fake)

        do {
            _ = try await service.connectWirelessDevice(
                host: "192.168.1.8;id",
                port: 5_555
            )
            XCTFail("Expected endpoint validation failure")
        } catch DeviceServiceError.invalidWirelessEndpoint {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await service.pairWirelessDevice(
                host: "192.168.1.8",
                port: 37_123,
                pairingCode: "12 3456"
            )
            XCTFail("Expected pairing code validation failure")
        } catch DeviceServiceError.invalidPairingCode {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
