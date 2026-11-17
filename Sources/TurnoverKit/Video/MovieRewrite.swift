@preconcurrency import AVFoundation
import Foundation

/// Rewrites a movie as an MP4 by moving samples from an `AVAssetReader` to an `AVAssetWriter`.
struct MovieRewrite {
    let source: URL
    let destination: URL

    init(_ source: URL, to destination: URL) {
        self.source = source
        self.destination = destination
    }

    func run() async throws {
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first,
              let videoFormat = try await video.load(.formatDescriptions).first
        else { throw ConversionError.notApplicable(source, format: "MP4") }
        let audio = try await asset.loadTracks(withMediaType: .audio).first

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        var lanes: [SamplePump.Lane] = []
        let videoOutput = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoInput.transform = try await video.load(.preferredTransform)
        lanes.append(.init(output: videoOutput, input: videoInput))

        if let audio, let audioFormat = try await audio.load(.formatDescriptions).first {
            let audioOutput = AVAssetReaderTrackOutput(track: audio, outputSettings: nil)
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormat)
            lanes.append(.init(output: audioOutput, input: audioInput))
        }

        for lane in lanes {
            lane.output.alwaysCopiesSampleData = false
            reader.add(lane.output)
            writer.add(lane.input)
        }
        try await SamplePump(reader: reader, writer: writer, lanes: lanes).run()
    }
}

/// Moves samples from reader outputs to writer inputs, one lane per track, until every lane runs
/// dry or something fails. All of its state lives on one serial queue.
final class SamplePump: @unchecked Sendable {
    struct Lane {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput
    }

    private let queue = DispatchQueue(label: "Turnover.SamplePump")
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let lanes: [Lane]
    private var running = 0
    private var continuation: CheckedContinuation<Void, any Error>?

    init(reader: AVAssetReader, writer: AVAssetWriter, lanes: [Lane]) {
        self.reader = reader
        self.writer = writer
        self.lanes = lanes
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { self.start(continuation) }
        }
    }

    private func start(_ continuation: CheckedContinuation<Void, any Error>) {
        self.continuation = continuation
        guard reader.startReading() else { return fail(reader.error) }
        guard writer.startWriting() else { return fail(writer.error) }
        writer.startSession(atSourceTime: .zero)
        running = lanes.count
        for index in lanes.indices {
            lanes[index].input.requestMediaDataWhenReady(on: queue) { self.pump(self.lanes[index]) }
        }
    }

    private func pump(_ lane: Lane) {
        guard continuation != nil else { return }
        while lane.input.isReadyForMoreMediaData {
            guard let sample = lane.output.copyNextSampleBuffer() else {
                if reader.status == .failed { return fail(reader.error) }
                lane.input.markAsFinished()
                running -= 1
                if running == 0 { finishWriting() }
                return
            }
            guard lane.input.append(sample) else { return fail(writer.error) }
        }
    }

    private func finishWriting() {
        writer.finishWriting {
            self.queue.async {
                if self.writer.status == .completed {
                    self.continuation?.resume()
                    self.continuation = nil
                } else {
                    self.fail(self.writer.error)
                }
            }
        }
    }

    private func fail(_ error: (any Error)?) {
        reader.cancelReading()
        if writer.status == .writing { writer.cancelWriting() }
        continuation?.resume(throwing: error ?? CocoaError(.fileWriteUnknown))
        continuation = nil
    }
}
