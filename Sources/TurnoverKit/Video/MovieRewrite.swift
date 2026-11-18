@preconcurrency import AVFoundation
import Foundation

/// Rewrites a movie as an MP4 by moving samples from an `AVAssetReader` to an `AVAssetWriter`.
/// Each stream is copied as is when it already plays everywhere (H.264, AAC) and re-encoded
/// otherwise. The movie's metadata, such as where and when it was recorded, comes along.
struct MovieRewrite {
    let source: URL
    let destination: URL

    init(_ source: URL, to destination: URL) {
        self.source = source
        self.destination = destination
    }

    func run(progress: ConversionProgress) async throws {
        let movie = try await MovieSource(source)
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: movie.asset) } catch { throw ConversionError.damaged(source) }
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        writer.metadata = movie.metadata

        var streams = [videoStream(movie.video)]
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

    private func videoStream(_ video: MovieSource.Video) -> SamplePump.Stream {
        let output: AVAssetReaderTrackOutput
        let input: AVAssetWriterInput
        if video.isWidelyPlayable {
            output = AVAssetReaderTrackOutput(track: video.track, outputSettings: nil)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: video.format)
        } else {
            output = AVAssetReaderTrackOutput(track: video.track, outputSettings: H264.decodingSettings)
            input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: H264.encodingSettings(
                    for: video.format.dimensions, frameRate: video.frameRate, sourceDataRate: video.dataRate))
        }
        input.transform = video.transform
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
