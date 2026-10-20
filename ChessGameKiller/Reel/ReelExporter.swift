import AVFoundation
import SwiftUI
import UIKit

/// Turns a highlight reel into a 1080×1920 video with Leo's voice, ready for
/// Instagram, TikTok or Messages.
@MainActor
enum ReelExporter {
    static let size = CGSize(width: 360, height: 640)
    static let scale: CGFloat = 3
    static let fps: Int32 = 30

    enum Failure: Error { case writer, frame }

    static func export(_ reel: GameReel, theme: BoardTheme) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory
        let silent = folder.appendingPathComponent("reel-silent-\(UUID().uuidString).mp4")
        let final = folder.appendingPathComponent("Chess highlights.mp4")
        try? FileManager.default.removeItem(at: final)

        try await writeFrames(reel, theme: theme, to: silent)
        if try await addVoice(reel, video: silent, to: final) {
            try? FileManager.default.removeItem(at: silent)
            return final
        }
        try FileManager.default.moveItem(at: silent, to: final)
        return final
    }

    // MARK: Pictures

    private static func writeFrames(_ reel: GameReel, theme: BoardTheme, to url: URL) async throws {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(pixels.width),
            AVVideoHeightKey: Int(pixels.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(pixels.width),
            kCVPixelBufferHeightKey as String: Int(pixels.height),
        ])
        guard writer.canAdd(input) else { throw Failure.writer }
        writer.add(input)
        guard writer.startWriting() else { throw Failure.writer }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(reel.length * Double(fps))
        for frame in 0..<frames {
            let time = Double(frame) / Double(fps)
            let renderer = ImageRenderer(content: ReelFrame(reel: reel, theme: theme, time: time)
                .frame(width: size.width, height: size.height))
            renderer.scale = scale
            guard let image = renderer.cgImage, let buffer = pixelBuffer(from: image, size: pixels, pool: adaptor.pixelBufferPool)
            else { throw Failure.frame }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
            // Let the screen breathe between frames.
            if frame % 10 == 0 { await Task.yield() }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw Failure.writer }
    }

    private static func pixelBuffer(from image: CGImage, size: CGSize, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }

    // MARK: Sound

    /// Lays Leo's recorded lines over the video. False when none of them are recorded.
    private static func addVoice(_ reel: GameReel, video: URL, to url: URL) async throws -> Bool {
        let clips = reel.narration.compactMap { cue -> (Double, URL)? in
            Bundle.main.url(forResource: CoachVoice.fileName(for: cue.text), withExtension: "mp3").map { (cue.time, $0) }
        }
        guard !clips.isEmpty else { return false }

        let composition = AVMutableComposition()
        let source = AVURLAsset(url: video)
        guard let videoTrack = try await source.loadTracks(withMediaType: .video).first,
              let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return false }
        let duration = try await source.load(.duration)
        try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)

        var free = CMTime.zero
        for (time, clipURL) in clips {
            let clip = AVURLAsset(url: clipURL)
            guard let track = try await clip.loadTracks(withMediaType: .audio).first else { continue }
            let length = try await clip.load(.duration)
            // Never overlap the previous line, and never run past the end of the video.
            let start = CMTimeMaximum(CMTime(seconds: time, preferredTimescale: 600), free)
            let room = CMTimeSubtract(duration, start)
            guard room > .zero else { break }
            let used = CMTimeMinimum(length, room)
            try compositionAudio.insertTimeRange(CMTimeRange(start: .zero, duration: used), of: track, at: start)
            free = CMTimeAdd(start, used)
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            return false
        }
        session.outputURL = url
        session.outputFileType = .mp4
        await session.export()
        return session.status == .completed
    }
}
