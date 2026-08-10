@preconcurrency import AVFoundation
import Foundation

enum RecordingSegmentMerger {
    static func merge(_ segmentURLs: [URL], to outputURL: URL) async throws {
        guard let firstURL = segmentURLs.first else {
            throw CaptureError.insufficientFrames
        }
        try? FileManager.default.removeItem(at: outputURL)

        guard segmentURLs.count > 1 else {
            try FileManager.default.moveItem(at: firstURL, to: outputURL)
            return
        }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CaptureError.videoEncodingFailed("无法创建录屏合并轨道")
        }

        var insertionTime = CMTime.zero
        for (index, segmentURL) in segmentURLs.enumerated() {
            let asset = AVURLAsset(url: segmentURL)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard duration.seconds.isFinite,
                  duration.seconds > 0,
                  let sourceTrack = tracks.first else {
                throw CaptureError.videoEncodingFailed("录屏分段无有效视频轨道")
            }
            if index == 0 {
                compositionTrack.preferredTransform = try await sourceTrack.load(
                    .preferredTransform
                )
            }
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceTrack,
                at: insertionTime
            )
            insertionTime = CMTimeAdd(insertionTime, duration)
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw CaptureError.videoEncodingFailed("无法创建录屏合并任务")
        }
        try await exporter.export(to: outputURL, as: .mp4)
    }
}
