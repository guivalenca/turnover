@preconcurrency import AVFoundation
import Foundation

/// Rewrites a movie as an MP4 by moving samples from an `AVAssetReader` to an `AVAssetWriter`.
/// Each stream is copied as is when it already plays everywhere (H.264, AAC) and re-encoded
/// otherwise; to make the movie smaller, its video is always re-encoded. The movie's metadata, such as where and when it was recorded, comes along.
struct MovieRewrite {
    let source: URL
    let destination: URL

    /// The quality to make the movie smaller at; nil to keep its own.
    let quality: VideoQuality?

    init(_ source: URL, to destination: URL, shrinkingTo quality: VideoQuality? = nil) {
        self.quality = quality
        self.source = source
        self.destination = destination
    }

    func run(progress: ConversionProgress) async throws {
        let movie = try await MovieSource(source, for: quality == nil ? .mp4 : .smaller)
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: movie.asset) } catch { throw ConversionError.damaged(source) }
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        writer.metadata = movie.metadata

        var streams = [videoStream(movie)]
        if let audio = movie.audio { streams.append(audioStream(audio)) }
        for stream in streams {
            stream.output.alwaysCopiesSampleData = false
            reader.add(stream.output)
            writer.add(stream.input)
        }

        let pump = SamplePump(reader: reader, writer: writer, streams: streams, duration: movie.duration, progress: progress)
        do {
            try await pump.run()
        } catch is SamplePump.ReadingFailed {
            throw ConversionError.damaged(source)
        }
    }

    private func videoStream(_ movie: MovieSource) -> SamplePump.Stream {
        let video = movie.video
        let output: AVAssetReaderTrackOutput
        let input: AVAssetWriterInput
        var transform = video.transform
        if let quality {
            let plan = SmallerPlan(movie, quality: quality)
            output = AVAssetReaderTrackOutput(track: video.track, outputSettings: H264.decodingSettings)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: H264.encodingSettings(for: plan, frameRate: video.frameRate))
            // The display matrix moves the turned frame back to the origin: by less, for a smaller one.
            transform.tx *= plan.scale
            transform.ty *= plan.scale
        } else if video.isWidelyPlayable {
            output = AVAssetReaderTrackOutput(track: video.track, outputSettings: nil)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: video.format)
        } else {
            output = AVAssetReaderTrackOutput(track: video.track, outputSettings: H264.decodingSettings)
            input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: H264.encodingSettings(
                    for: video.format.dimensions, frameRate: video.frameRate, sourceDataRate: video.dataRate))
        }
        input.transform = transform
        return SamplePump.Stream(output: output, input: input, reportsProgress: true)
    }

    private func audioStream(_ audio: MovieSource.Audio) -> SamplePump.Stream {
        if AAC.isWidelyPlayable(audio.format) {
            return SamplePump.Stream(
                output: AVAssetReaderTrackOutput(track: audio.track, outputSettings: nil),
                input: AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audio.format),
                reportsProgress: false)
        }
        return SamplePump.Stream(
            output: AVAssetReaderTrackOutput(track: audio.track, outputSettings: AAC.decodingSettings(for: audio.format)),
            input: AVAssetWriterInput(mediaType: .audio, outputSettings: AAC.encodingSettings(for: audio.format)),
            reportsProgress: false)
    }
}
