import AVFoundation
import Foundation
import ImageIO

struct MediaFileMetadata: Sendable {
    let pixelWidth: Int?
    let pixelHeight: Int?
    let byteCount: Int64?
    let duration: TimeInterval?
}

enum MediaMetadataReader {
    static func image(at url: URL) -> MediaFileMetadata {
        let byteCount = fileSize(at: url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else {
            return MediaFileMetadata(
                pixelWidth: nil,
                pixelHeight: nil,
                byteCount: byteCount,
                duration: nil
            )
        }
        return MediaFileMetadata(
            pixelWidth: (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            pixelHeight: (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            byteCount: byteCount,
            duration: nil
        )
    }

    static func video(at url: URL) async -> MediaFileMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        let track = try? await asset.loadTracks(withMediaType: .video).first
        let naturalSize = try? await track?.load(.naturalSize)
        let transform = try? await track?.load(.preferredTransform)
        let transformedSize = naturalSize.map { size in
            transform.map { size.applying($0) } ?? size
        }
        return MediaFileMetadata(
            pixelWidth: transformedSize.map { Int(abs($0.width.rounded())) },
            pixelHeight: transformedSize.map { Int(abs($0.height.rounded())) },
            byteCount: fileSize(at: url),
            duration: duration.map(CMTimeGetSeconds).flatMap { $0.isFinite ? $0 : nil }
        )
    }

    private static func fileSize(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }
}
