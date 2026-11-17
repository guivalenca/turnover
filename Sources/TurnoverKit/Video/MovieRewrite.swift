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

        var lanes = [videoLane(movie.video)]
        if let audio = movie.audio { lanes.append(audioLane(audio)) }
        for lane in lanes {
            lane.output.alwaysCopiesSampleData = false
            reader.add(lane.output)
            writer.add(lane.input)
        }

        let pump = SamplePump(reader: reader, writer: writer, lanes: lanes, duration: movie.duration, progress: progress)
        do {
            try await pump.run()
        } catch is SamplePump.ReadingFailed {
            throw ConversionError.damaged(source)
        }
    }

    private func videoLane(_ video: MovieSource.Video) -> SamplePump.Lane {
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
        return SamplePump.Lane(output: output, input: input, reportsProgress: true)
    }

    private func audioLane(_ audio: MovieSource.Audio) -> SamplePump.Lane {
        if AAC.isWidelyPlayable(audio.format) {
            return SamplePump.Lane(
                output: AVAssetReaderTrackOutput(track: audio.track, outputSettings: nil),
                input: AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audio.format),
                reportsProgress: false)
        }
        return SamplePump.Lane(
            output: AVAssetReaderTrackOutput(track: audio.track, outputSettings: AAC.decodingSettings(for: audio.format)),
            input: AVAssetWriterInput(mediaType: .audio, outputSettings: AAC.encodingSettings(for: audio.format)),
            reportsProgress: false)
    }
}
