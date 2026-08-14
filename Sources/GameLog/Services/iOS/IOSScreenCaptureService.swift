@preconcurrency import AVFoundation
import CoreImage
import CoreMediaIO
import Foundation

struct IOSScreenCaptureService: Sendable {
    func takeScreenshot(
        device: AndroidDevice,
        destinationDirectory: URL
    ) async throws -> CaptureEvidence {
        guard device.platform == .iOS else {
            throw IOSScreenCaptureError.invalidDevice
        }
        guard await requestVideoAccess() else {
            throw IOSScreenCaptureError.cameraAccessDenied
        }
        try enableIOSScreenCaptureDevices()
        let captureDevice = try await waitForCaptureDevice(
            serial: device.serial,
            deviceName: device.model
        )
        let controller = IOSSingleFrameCapture(device: captureDevice)
        let pngData = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await controller.capture() }
            group.addTask {
                try await Task.sleep(for: .seconds(12))
                throw IOSScreenCaptureError.frameTimeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
        guard pngData.starts(with: [0x89, 0x50, 0x4E, 0x47]) else {
            throw IOSScreenCaptureError.invalidImage
        }

        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        let fileURL = destinationDirectory.appending(
            path: "Screenshot-\(Self.timestamp()).png"
        )
        try pngData.write(to: fileURL, options: .atomic)
        let thumbnailURL = try? await ScreenshotThumbnailer.create(
            pngData: pngData,
            sourceName: fileURL.deletingPathExtension().lastPathComponent,
            screenshotsDirectory: destinationDirectory
        )
        let metadata = MediaMetadataReader.image(at: fileURL)
        return CaptureEvidence(
            kind: .screenshot,
            fileURL: fileURL,
            thumbnailURL: thumbnailURL,
            deviceSerial: device.serial,
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight,
            byteCount: metadata.byteCount
        )
    }

    private func requestVideoAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }

    private func enableIOSScreenCaptureDevices() throws {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var enabled: UInt32 = 1
        let status = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &enabled
        )
        guard status == noErr else {
            throw IOSScreenCaptureError.cannotEnableCaptureDevices(status)
        }
    }

    private func waitForCaptureDevice(
        serial: String,
        deviceName: String?
    ) async throws -> AVCaptureDevice {
        for _ in 0..<24 {
            try Task.checkCancellation()
            if let device = matchingCaptureDevice(serial: serial, deviceName: deviceName) {
                return device
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw IOSScreenCaptureError.screenDeviceUnavailable
    }

    private func matchingCaptureDevice(
        serial: String,
        deviceName: String?
    ) -> AVCaptureDevice? {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )
        if let exactIdentifier = session.devices.first(where: { $0.uniqueID == serial }) {
            return exactIdentifier
        }
        guard let deviceName else { return nil }
        return session.devices.first {
            $0.localizedName.compare(
                deviceName,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }

    private static func timestamp() -> String {
        timestampFormatter.string(from: Date())
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss-SSS"
        return formatter
    }()
}

enum IOSScreenCaptureError: LocalizedError, Sendable {
    case invalidDevice
    case cameraAccessDenied
    case cannotEnableCaptureDevices(OSStatus)
    case screenDeviceUnavailable
    case cannotConfigureSession
    case frameTimeout
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidDevice:
            String(localized: "所选设备不是 iOS 设备。")
        case .cameraAccessDenied:
            String(localized: "需要允许相机访问，才能通过 macOS 的 iPhone 屏幕采集通道截图。")
        case .cannotEnableCaptureDevices:
            String(localized: "无法启用 iOS 屏幕采集设备。")
        case .screenDeviceUnavailable:
            String(localized: "未找到 iPhone 屏幕采集源。请解锁设备、确认信任此 Mac，并重新插拔 USB 线后重试。")
        case .cannotConfigureSession:
            String(localized: "无法建立 iPhone 屏幕采集会话。")
        case .frameTimeout:
            String(localized: "等待 iPhone 屏幕画面超时。请保持设备解锁后重试。")
        case .invalidImage:
            String(localized: "iPhone 返回的截图数据无效。")
        }
    }
}

private final class IOSSingleFrameCapture: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable {
    private let device: AVCaptureDevice
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.kkxx.gamelog.ios-screen-capture")
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var didFinish = false

    init(device: AVCaptureDevice) {
        self.device = device
    }

    func capture() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
                queue.async { [weak self] in self?.start() }
            }
        } onCancel: {
            finish(throwing: CancellationError())
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = imageContext.pngRepresentation(
                of: CIImage(cvPixelBuffer: pixelBuffer),
                format: .RGBA8,
                colorSpace: colorSpace
              ) else {
            finish(throwing: IOSScreenCaptureError.invalidImage)
            return
        }
        finish(returning: data)
    }

    private func start() {
        do {
            session.beginConfiguration()
            session.sessionPreset = .high
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                throw IOSScreenCaptureError.cannotConfigureSession
            }
            session.addInput(input)
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(output)
            session.commitConfiguration()
            session.startRunning()
        } catch {
            finish(throwing: error)
        }
    }

    private func finish(returning data: Data) {
        finish(with: .success(data))
    }

    private func finish(throwing error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<Data, Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        output.setSampleBufferDelegate(nil, queue: nil)
        if session.isRunning {
            session.stopRunning()
        }
        continuation?.resume(with: result)
    }
}
