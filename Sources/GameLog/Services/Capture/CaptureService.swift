import Foundation

struct CaptureService: Sendable {
    let executor: any ADBExecuting
    let rootDirectory: URL

    init(executor: any ADBExecuting, rootDirectory: URL? = nil) {
        self.executor = executor
        self.rootDirectory = rootDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Movies/GameLog", directoryHint: .isDirectory)
    }

    func takeScreenshot(serial: String, destinationDirectory: URL? = nil) async throws -> CaptureEvidence {
        let result = try await executor.run(
            ["exec-out", "screencap", "-p"],
            serial: serial,
            timeout: .seconds(10)
        )
        guard result.stdout.starts(with: [0x89, 0x50, 0x4E, 0x47]) else {
            throw CaptureError.invalidScreenshot
        }
        let directory = try writableDirectory(destinationDirectory, serial: serial)
        let url = directory.appending(path: "Screenshot-\(timestamp()).png")
        try result.stdout.write(to: url, options: .atomic)
        let thumbnailURL = try? await ScreenshotThumbnailer.create(
            pngData: result.stdout,
            sourceName: url.deletingPathExtension().lastPathComponent,
            screenshotsDirectory: directory
        )
        let metadata = MediaMetadataReader.image(at: url)
        return CaptureEvidence(
            kind: .screenshot,
            fileURL: url,
            thumbnailURL: thumbnailURL,
            deviceSerial: serial,
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight,
            byteCount: metadata.byteCount
        )
    }

    func recordScreen(
        serial: String,
        size: String? = nil,
        bitRate: Int? = nil,
        destinationDirectory: URL? = nil
    ) async throws -> CaptureEvidence {
        let token = UUID().uuidString.lowercased()
        let directory = try writableDirectory(destinationDirectory, serial: serial)
        let localURL = directory.appending(path: "Recording-\(timestamp()).mp4")
        let segmentDirectory = directory.appending(
            path: ".Recording-\(token)-segments",
            directoryHint: .isDirectory
        )
        let startedAt = Date()
        try FileManager.default.createDirectory(
            at: segmentDirectory,
            withIntermediateDirectories: true
        )

        do {
            _ = try await executor.run(
                ["shell", "test", "-w", "/sdcard"],
                serial: serial,
                timeout: .seconds(5)
            )
            let segments = try await recordUsingNativeSegments(
                serial: serial,
                size: size,
                bitRate: bitRate,
                segmentDirectory: segmentDirectory
            )
            return try await finalizeNativeSegments(
                segments,
                segmentDirectory: segmentDirectory,
                outputURL: localURL,
                serial: serial,
                startedAt: startedAt
            )
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: segmentDirectory)
            throw CancellationError()
        } catch let error as CaptureError {
            if case .recoverableRecording = error {
                throw error
            }
            try? FileManager.default.removeItem(at: segmentDirectory)
            return try await recordUsingScreenshotFallback(
                serial: serial,
                outputURL: localURL
            )
        } catch {
            try? FileManager.default.removeItem(at: segmentDirectory)
            return try await recordUsingScreenshotFallback(
                serial: serial,
                outputURL: localURL
            )
        }
    }

    func recoverRecording(
        serial: String,
        remotePath: String,
        localFileName: String,
        destinationDirectory: URL
    ) async throws -> CaptureEvidence {
        guard Self.isValidRemoteRecordingPath(remotePath),
              Self.isValidLocalRecordingName(localFileName) else {
            throw CaptureError.invalidRecoveryMetadata
        }
        let directory = try writableDirectory(destinationDirectory, serial: serial)
        let localURL = directory.appending(path: localFileName)
        let temporaryURL = directory.appending(
            path: ".\(UUID().uuidString.lowercased()).recovery.partial"
        )
        try? FileManager.default.removeItem(at: temporaryURL)
        do {
            _ = try await executor.run(
                ["pull", remotePath, temporaryURL.path],
                serial: serial,
                timeout: .seconds(60)
            )
            let metadata = await MediaMetadataReader.video(at: temporaryURL)
            guard let byteCount = metadata.byteCount, byteCount > 0,
                  metadata.duration.map({ $0 > 0 }) == true else {
                throw CaptureError.emptyRecording
            }
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: localURL)
            _ = try? await executor.run(["shell", "rm", remotePath], serial: serial)
            return CaptureEvidence(
                kind: .recording,
                fileURL: localURL,
                deviceSerial: serial,
                duration: metadata.duration,
                pixelWidth: metadata.pixelWidth,
                pixelHeight: metadata.pixelHeight,
                byteCount: metadata.byteCount
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw CaptureError.recoverableRecording(
                remotePath: remotePath,
                localFileName: localFileName,
                reason: error.localizedDescription
            )
        }
    }

    private func recordUsingScreenshotFallback(
        serial: String,
        outputURL: URL
    ) async throws -> CaptureEvidence {
        let targetFPS = 3.0
        let startedAt = Date()
        var encoder: ScreenshotVideoEncoder.EncodingSession?
        var frameCount = 0
        let temporaryURL = outputURL
            .deletingLastPathComponent()
            .appending(path: ".\(outputURL.lastPathComponent).partial")
        try? FileManager.default.removeItem(at: temporaryURL)

        do {
            while true {
                try Task.checkCancellation()
                let result = try await executor.run(
                    ["exec-out", "screencap", "-p"],
                    serial: serial,
                    timeout: .seconds(10)
                )
                guard result.stdout.starts(with: [0x89, 0x50, 0x4E, 0x47]) else {
                    throw CaptureError.invalidScreenshot
                }
                let presentationTime = Date().timeIntervalSince(startedAt)
                if encoder == nil {
                    encoder = try await ScreenshotVideoEncoder.start(
                        firstFrameData: result.stdout,
                        outputURL: temporaryURL
                    )
                }
                if let encoder {
                    try await ScreenshotVideoEncoder.append(
                        pngData: result.stdout,
                        presentationTime: presentationTime,
                        to: encoder
                    )
                }
                frameCount += 1

                let nextFrameTime = Double(frameCount) / targetFPS
                let delay = nextFrameTime - Date().timeIntervalSince(startedAt)
                if delay > 0 {
                    try await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
                }
            }
        } catch is CancellationError {
            // A user stop keeps frames already encoded and finalizes them below.
        } catch {
            if let encoder {
                await ScreenshotVideoEncoder.cancel(encoder)
            }
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }

        guard frameCount >= 2, let encoder else {
            if let encoder {
                await ScreenshotVideoEncoder.cancel(encoder)
            }
            try? FileManager.default.removeItem(at: temporaryURL)
            throw CaptureError.insufficientFrames
        }
        do {
            try await ScreenshotVideoEncoder.finish(encoder)
        } catch {
            await ScreenshotVideoEncoder.cancel(encoder)
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue > 0 else {
            throw CaptureError.emptyRecording
        }
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        let metadata = await MediaMetadataReader.video(at: outputURL)
        return CaptureEvidence(
            kind: .recording,
            fileURL: outputURL,
            deviceSerial: serial,
            duration: metadata.duration
                ?? max(0, Date().timeIntervalSince(startedAt)),
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight,
            byteCount: metadata.byteCount
        )
    }

    private func recordUsingNativeSegments(
        serial: String,
        size: String?,
        bitRate: Int?,
        segmentDirectory: URL
    ) async throws -> [URL] {
        var segmentURLs: [URL] = []
        var segmentIndex = 0

        while true {
            if Task.isCancelled {
                guard !segmentURLs.isEmpty else {
                    throw CancellationError()
                }
                return segmentURLs
            }

            let token = UUID().uuidString.lowercased()
            let remotePath = "/sdcard/gamelog-\(token).mp4"
            let temporaryURL = segmentDirectory.appending(path: ".segment-\(token).partial")
            let segmentURL = segmentDirectory.appending(
                path: "segment-\(segmentIndex.formatted(.number.grouping(.never))).mp4"
            )
            let segmentStartedAt = Date()
            var arguments = ["shell", "screenrecord"]
            if let size {
                arguments += ["--size", size]
            }
            if let bitRate {
                arguments += ["--bit-rate", String(bitRate)]
            }
            arguments += [
                "--time-limit",
                String(Self.nativeSegmentDuration),
                remotePath
            ]

            do {
                _ = try await executor.run(
                    arguments,
                    serial: serial,
                    timeout: .seconds(Self.nativeSegmentDuration + 15)
                )
                let segment = try await pullNativeRecording(
                    serial: serial,
                    remotePath: remotePath,
                    temporaryURL: temporaryURL,
                    localURL: segmentURL,
                    startedAt: segmentStartedAt
                )
                segmentURLs.append(segment.fileURL)
                segmentIndex += 1
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: temporaryURL)
                let segment = try await finishCancelledNativeRecording(
                    serial: serial,
                    remotePath: remotePath,
                    temporaryURL: temporaryURL,
                    localURL: segmentURL,
                    startedAt: segmentStartedAt
                )
                segmentURLs.append(segment.fileURL)
                return segmentURLs
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw error
            }
        }
    }

    private func pullNativeRecording(
        serial: String,
        remotePath: String,
        temporaryURL: URL,
        localURL: URL,
        startedAt: Date
    ) async throws -> CaptureEvidence {
        _ = try await executor.run(
            ["pull", remotePath, temporaryURL.path],
            serial: serial,
            timeout: .seconds(60)
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue > 0 else {
            throw CaptureError.emptyRecording
        }
        try FileManager.default.moveItem(at: temporaryURL, to: localURL)
        _ = try? await executor.run(["shell", "rm", remotePath], serial: serial)
        let metadata = await MediaMetadataReader.video(at: localURL)
        return CaptureEvidence(
            kind: .recording,
            fileURL: localURL,
            deviceSerial: serial,
            duration: metadata.duration ?? max(0, Date().timeIntervalSince(startedAt)),
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight,
            byteCount: metadata.byteCount
        )
    }

    private func finalizeNativeSegments(
        _ segmentURLs: [URL],
        segmentDirectory: URL,
        outputURL: URL,
        serial: String,
        startedAt: Date
    ) async throws -> CaptureEvidence {
        try await Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: segmentDirectory) }
            try await RecordingSegmentMerger.merge(segmentURLs, to: outputURL)
            let metadata = await MediaMetadataReader.video(at: outputURL)
            return CaptureEvidence(
                kind: .recording,
                fileURL: outputURL,
                deviceSerial: serial,
                duration: metadata.duration ?? max(0, Date().timeIntervalSince(startedAt)),
                pixelWidth: metadata.pixelWidth,
                pixelHeight: metadata.pixelHeight,
                byteCount: metadata.byteCount
            )
        }.value
    }

    private func finishCancelledNativeRecording(
        serial: String,
        remotePath: String,
        temporaryURL: URL,
        localURL: URL,
        startedAt: Date
    ) async throws -> CaptureEvidence {
        let executor = executor
        return try await Task.detached(priority: .userInitiated) {
            var lastError: Error?
            for attempt in 0..<3 {
                if attempt > 0 {
                    try await Task.sleep(for: .milliseconds(500))
                }
                do {
                    _ = try await executor.run(
                        ["pull", remotePath, temporaryURL.path],
                        serial: serial,
                        timeout: .seconds(60)
                    )
                    let attributes = try FileManager.default.attributesOfItem(
                        atPath: temporaryURL.path
                    )
                    guard let size = attributes[.size] as? NSNumber, size.intValue > 0 else {
                        throw CaptureError.emptyRecording
                    }
                    try FileManager.default.moveItem(at: temporaryURL, to: localURL)
                    _ = try? await executor.run(["shell", "rm", remotePath], serial: serial)
                    let metadata = await MediaMetadataReader.video(at: localURL)
                    return CaptureEvidence(
                        kind: .recording,
                        fileURL: localURL,
                        deviceSerial: serial,
                        duration: metadata.duration
                            ?? max(0, Date().timeIntervalSince(startedAt)),
                        pixelWidth: metadata.pixelWidth,
                        pixelHeight: metadata.pixelHeight,
                        byteCount: metadata.byteCount
                    )
                } catch {
                    lastError = error
                }
            }
            throw CaptureError.recoverableRecording(
                remotePath: remotePath,
                localFileName: localURL.lastPathComponent,
                reason: lastError?.localizedDescription ?? "下载失败"
            )
        }.value
    }

    private func sessionDirectory(serial: String) throws -> URL {
        let safeSerial = serial.replacingOccurrences(of: "/", with: "-")
        let url = rootDirectory
            .appending(path: dayStamp(), directoryHint: .isDirectory)
            .appending(path: safeSerial, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writableDirectory(_ requested: URL?, serial: String) throws -> URL {
        if let requested {
            try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: true)
            guard FileManager.default.isWritableFile(atPath: requested.path) else {
                throw CaptureError.directoryNotWritable
            }
            return requested
        }
        return try sessionDirectory(serial: serial)
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    private static func isValidRemoteRecordingPath(_ path: String) -> Bool {
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return remoteRecordingPathExpression.firstMatch(in: path, range: range)?.range == range
    }

    private static func isValidLocalRecordingName(_ name: String) -> Bool {
        guard name == URL(fileURLWithPath: name).lastPathComponent,
              name.utf8.count <= 128 else {
            return false
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return localRecordingNameExpression.firstMatch(in: name, range: range)?.range == range
    }

    private static let remoteRecordingPathExpression = try! NSRegularExpression(
        pattern: #"^/sdcard/gamelog-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.mp4$"#
    )

    private static let localRecordingNameExpression = try! NSRegularExpression(
        pattern: #"^Recording-[0-9]{8}-[0-9]{6}(?:-[0-9]{3})?\.mp4$"#
    )

    private func dayStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static let nativeSegmentDuration = 180
}

enum CaptureError: LocalizedError, Sendable {
    case invalidScreenshot
    case emptyRecording
    case insufficientFrames
    case videoEncodingFailed(String)
    case directoryNotWritable
    case invalidRecoveryMetadata
    case recoverableRecording(remotePath: String, localFileName: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidScreenshot: "设备没有返回有效的 PNG 截图。"
        case .emptyRecording: "录屏文件为空。"
        case .insufficientFrames: "设备返回的画面帧不足，无法生成录屏。"
        case .videoEncodingFailed(let message): "录屏编码失败：\(message)"
        case .directoryNotWritable: "会话媒体目录不可写。"
        case .invalidRecoveryMetadata: "待恢复录屏的路径信息无效，已拒绝执行设备命令。"
        case .recoverableRecording(let remotePath, _, let reason):
            "录屏仍保留在设备 \(remotePath)，可重连后恢复：\(reason)"
        }
    }
}
