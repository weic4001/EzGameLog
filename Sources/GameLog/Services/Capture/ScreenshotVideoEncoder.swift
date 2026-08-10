@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

struct CapturedVideoFrame: Sendable {
    let pngData: Data
    let presentationTime: TimeInterval
}

enum ScreenshotVideoEncoder {
    final class EncodingSession: @unchecked Sendable {
        private let writer: AVAssetWriter
        private let input: AVAssetWriterInput
        private let adaptor: AVAssetWriterInputPixelBufferAdaptor
        private let outputSize: (width: Int, height: Int)
        private var isFinished = false

        init(firstFrameData: Data, outputURL: URL) throws {
            guard let source = CGImageSourceCreateWithData(firstFrameData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw CaptureError.videoEncodingFailed("无法解码首帧")
            }

            outputSize = ScreenshotVideoEncoder.scaledSize(
                width: image.width,
                height: image.height
            )
            try? FileManager.default.removeItem(at: outputURL)
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outputSize.width,
                AVVideoHeightKey: outputSize.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outputSize.width,
                kCVPixelBufferHeightKey as String: outputSize.height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: attributes
            )

            guard writer.canAdd(input) else {
                throw CaptureError.videoEncodingFailed("系统不接受 H.264 输出参数")
            }
            writer.add(input)
            guard writer.startWriting() else {
                throw CaptureError.videoEncodingFailed(
                    writer.error?.localizedDescription ?? "无法启动编码器"
                )
            }
            writer.startSession(atSourceTime: .zero)
        }

        func append(pngData: Data, presentationTime: TimeInterval) throws {
            guard !isFinished, writer.status == .writing else {
                throw CaptureError.videoEncodingFailed(
                    writer.error?.localizedDescription ?? "编码器不在写入状态"
                )
            }
            guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw CaptureError.videoEncodingFailed("无法解码视频帧")
            }
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else {
                    throw CaptureError.videoEncodingFailed(
                        writer.error?.localizedDescription ?? "编码器异常"
                    )
                }
                Thread.sleep(forTimeInterval: 0.002)
            }
            guard let pixelBuffer = ScreenshotVideoEncoder.makePixelBuffer(
                image: image,
                width: outputSize.width,
                height: outputSize.height,
                pool: adaptor.pixelBufferPool
            ) else {
                throw CaptureError.videoEncodingFailed("无法创建视频帧")
            }
            let time = CMTime(
                seconds: max(0, presentationTime),
                preferredTimescale: 600
            )
            guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
                throw CaptureError.videoEncodingFailed(
                    writer.error?.localizedDescription ?? "写入视频帧失败"
                )
            }
        }

        func finish() throws {
            guard !isFinished else { return }
            isFinished = true
            input.markAsFinished()
            let semaphore = DispatchSemaphore(value: 0)
            writer.finishWriting {
                semaphore.signal()
            }
            semaphore.wait()
            guard writer.status == .completed else {
                throw CaptureError.videoEncodingFailed(
                    writer.error?.localizedDescription ?? "编码未完成"
                )
            }
        }

        func cancel() {
            guard !isFinished else { return }
            isFinished = true
            writer.cancelWriting()
        }
    }

    static func start(firstFrameData: Data, outputURL: URL) async throws -> EncodingSession {
        try await Task.detached(priority: .userInitiated) {
            try EncodingSession(firstFrameData: firstFrameData, outputURL: outputURL)
        }.value
    }

    static func append(
        pngData: Data,
        presentationTime: TimeInterval,
        to session: EncodingSession
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try session.append(
                pngData: pngData,
                presentationTime: presentationTime
            )
        }.value
    }

    static func finish(_ session: EncodingSession) async throws {
        try await Task.detached(priority: .userInitiated) {
            try session.finish()
        }.value
    }

    static func cancel(_ session: EncodingSession) async {
        await Task.detached(priority: .utility) {
            session.cancel()
        }.value
    }

    static func encode(frames: [CapturedVideoFrame], outputURL: URL) async throws {
        guard let firstFrame = frames.first else {
            throw CaptureError.insufficientFrames
        }
        let session = try await start(
            firstFrameData: firstFrame.pngData,
            outputURL: outputURL
        )
        do {
            for frame in frames {
                try await append(
                    pngData: frame.pngData,
                    presentationTime: frame.presentationTime,
                    to: session
                )
            }
            try await finish(session)
        } catch {
            await cancel(session)
            throw error
        }
    }

    private static func scaledSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let scale = min(1, min(720.0 / Double(width), 1_280.0 / Double(height)))
        let scaledWidth = max(2, Int(Double(width) * scale) / 2 * 2)
        let scaledHeight = max(2, Int(Double(height) * scale) / 2 * 2)
        return (scaledWidth, scaledHeight)
    }

    private static func makePixelBuffer(
        image: CGImage,
        width: Int,
        height: Int,
        pool: CVPixelBufferPool?
    ) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status: CVReturn
        if let pool {
            status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            status = CVPixelBufferCreate(
                nil,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                nil,
                &buffer
            )
        }
        guard status == kCVReturnSuccess, let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
