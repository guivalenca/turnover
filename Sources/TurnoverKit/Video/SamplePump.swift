@preconcurrency import AVFoundation
import Foundation
import Synchronization

/// Moves samples from reader outputs to writer inputs, one lane per track, until every lane runs
/// dry, something fails or the task is cancelled. All of its state lives on one serial queue,
/// except the cancellation flag, which is checked between samples.
final class SamplePump: @unchecked Sendable {
    struct Lane {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput
        /// Whether this lane's timestamps measure progress. The video lane does: it is the slow one.
        let reportsProgress: Bool
    }

    private let queue = DispatchQueue(label: "Turnover.SamplePump")
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let lanes: [Lane]
    private let duration: CMTime
    private let progress: ConversionProgress
    private var running = 0
    private var continuation: CheckedContinuation<Void, any Error>?
    private let isCancelled = Atomic(false)

    /// The source couldn't be read to the end: it is damaged or can't be decoded.
    struct ReadingFailed: Error {
        let underlying: (any Error)?
    }

    init(reader: AVAssetReader, writer: AVAssetWriter, lanes: [Lane], duration: CMTime, progress: ConversionProgress) {
        self.reader = reader
        self.writer = writer
        self.lanes = lanes
        self.duration = duration
        self.progress = progress
    }

    /// Runs until the output is complete. Throws `ReadingFailed` when the source can't be read,
    /// the writer's error when the output can't be written, and `CancellationError` within a
    /// sample of the task being cancelled.
    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { self.start(continuation) }
            }
        } onCancel: {
            isCancelled.store(true, ordering: .relaxed)
            // Wakes a pump that is waiting for the writer rather than looping over samples.
            queue.async { self.stopIfCancelled() }
        }
    }

    private func start(_ continuation: CheckedContinuation<Void, any Error>) {
        self.continuation = continuation
        if stopIfCancelled() { return }
        guard reader.startReading() else { return fail(ReadingFailed(underlying: reader.error)) }
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
            if stopIfCancelled() { return }
            guard let sample = lane.output.copyNextSampleBuffer() else {
                if reader.status == .failed { return fail(ReadingFailed(underlying: reader.error)) }
                lane.input.markAsFinished()
                running -= 1
                if running == 0 { finishWriting() }
                return
            }
            guard lane.input.append(sample) else { return fail(writer.error) }
            if lane.reportsProgress { report(sample) }
        }
    }

    /// Progress is how much of the movie's duration has been written, up to the end of `sample`.
    /// Decoded frames have no duration, so for them it is up to the frame's start.
    private func report(_ sample: CMSampleBuffer) {
        guard duration.seconds > 0 else { return }
        var end = sample.presentationTimeStamp
        if sample.duration.isNumeric { end = end + sample.duration }
        if end.isNumeric { progress.report(end.seconds / duration.seconds) }
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

    /// Fails with `CancellationError` if the task was cancelled and the pump is still running.
    @discardableResult
    private func stopIfCancelled() -> Bool {
        guard isCancelled.load(ordering: .relaxed), continuation != nil else { return false }
        fail(CancellationError())
        return true
    }

    private func fail(_ error: (any Error)?) {
        reader.cancelReading()
        if writer.status == .writing { writer.cancelWriting() }
        continuation?.resume(throwing: error ?? CocoaError(.fileWriteUnknown))
        continuation = nil
    }
}
