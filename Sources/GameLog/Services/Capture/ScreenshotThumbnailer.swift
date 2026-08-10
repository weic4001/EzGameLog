import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenshotThumbnailer {
    static func create(
        pngData: Data,
        sourceName: String,
        screenshotsDirectory: URL
    ) async throws -> URL {
        try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 480
                    ] as CFDictionary
                  ) else {
                throw CaptureError.invalidScreenshot
            }
            let directory = screenshotsDirectory
                .appending(path: ".thumbnails", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "\(sourceName)-thumb.png")
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                throw CaptureError.invalidScreenshot
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw CaptureError.invalidScreenshot
            }
            return url
        }.value
    }
}
