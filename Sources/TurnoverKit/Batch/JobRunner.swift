import Foundation
import Observation

/// Runs batches of conversions. The app keeps one for everything it converts, so that its limits
/// hold across batches: images convert side by side, one per processor core, and videos at most
/// two at a time.
@MainActor @Observable
public final class JobRunner {
    /// The batches still running, oldest first. A batch leaves the list when its last job ends.
    public private(set) var batches: [Batch] = []

    @ObservationIgnored private let converter: Converter
    @ObservationIgnored private var lanes: [Lane: LaneState] = [
        .images: LaneState(limit: ProcessInfo.processInfo.activeProcessorCount),
        .videos: LaneState(limit: 2),
    ]

    public init(converter: Converter = Converter()) {
        self.converter = converter
    }

    /// Starts converting `files` and returns at once. Each file is converted by the first of
    /// `targets` that accepts it, for example PNG for the images and MP4 for the videos. Files
    /// no target fits are skipped.
    ///
    /// Observe the batch from the main actor. `reporting`, if given, also receives each job's
    /// progress as the conversion reports it (the job's index in `files`, and the fraction), on
    /// the conversion's thread: for a display that can't count on the main actor being free,
    /// such as a terminal's progress line. Values follow `Converter.convert`'s rules.
    @discardableResult
    public func run(
        _ files: [URL], to targets: [any ConversionAction],
        reporting: (@Sendable (_ job: Int, _ fraction: Double) -> Void)? = nil
    ) -> Batch {
        precondition(!targets.isEmpty, "a batch needs at least one target")
        let batch = Batch(jobs: files.map(Job.init(source:)))
        guard !batch.isFinished else { return batch }  // no files
        batches.append(batch)
        batch.whenFinished { [weak self] batch in self?.batches.removeAll { $0 === batch } }
        Task {
            // One file at a time, so jobs start in the order given.
            for (index, job) in batch.jobs.enumerated() {
                let route = await Self.route(job.source, to: targets)
                guard !job.isFinished else { continue }  // cancelled meanwhile
                switch route {
                case .convert(let file, let action):
                    let lane: Lane = file.kind == .video ? .videos : .images
                    let progress: @Sendable (Double) -> Void = { [job] fraction in
                        reporting?(index, fraction)
                        job.report(fraction)
                    }
                    lanes[lane]!.queue.append(Queued(job: job, file: file, action: action, progress: progress))
                    startQueuedJobs()
                case .end(let state):
                    job.end(as: state)
                }
            }
        }
        return batch
    }

    // MARK: - Scheduling

    private enum Lane { case images, videos }

    private struct LaneState {
        let limit: Int
        var running = 0
        var queue: [Queued] = []
    }

    private struct Queued {
        let job: Job
        let file: SourceFile
        let action: any ConversionAction
        let progress: @Sendable (Double) -> Void
    }

    private func startQueuedJobs() {
        for lane in lanes.keys {
            while lanes[lane]!.running < lanes[lane]!.limit, !lanes[lane]!.queue.isEmpty {
                let queued = lanes[lane]!.queue.removeFirst()
                guard !queued.job.isFinished else { continue }  // cancelled while it waited
                start(queued, in: lane)
            }
        }
    }

    private func start(_ queued: Queued, in lane: Lane) {
        lanes[lane]!.running += 1
        let converter = converter
        queued.job.start(Task {
            let state = await Self.convert(queued.file, with: queued.action, by: converter, progress: queued.progress)
            lanes[lane]!.running -= 1
            queued.job.end(as: state)
            startQueuedJobs()
        })
    }

    // MARK: - Converting, off the main actor

    private enum Route {
        case convert(SourceFile, any ConversionAction)
        case end(Job.State)
    }

    private nonisolated static func route(_ source: URL, to targets: [any ConversionAction]) async -> Route {
        do {
            let file = try SourceFile(source)
            guard let action = targets.first(where: { $0.accepts(file) }) else {
                return .end(.skipped(skipReason(file, targets)))
            }
            return .convert(file, action)
        } catch {
            return .end(.failed(reason: error.localizedDescription))
        }
    }

    private nonisolated static func convert(
        _ file: SourceFile, with action: any ConversionAction, by converter: Converter,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> Job.State {
        do {
            return .converted(try await converter.convert(file, with: action, progress: progress))
        } catch is CancellationError {
            return .cancelled
        } catch let error as ConversionError {
            return .failed(reason: error.localizedDescription)
        } catch {
            // Writing failed: no room, no permission, an encoder missing, …
            let detail = (error as? POSIXError).map { String(cString: strerror($0.code.rawValue)) }
                ?? error.localizedDescription
            return .failed(reason: "\(file.url.lastPathComponent): couldn't write the \(action.name) (\(detail))")
        }
    }

    /// Why no target fits `file`: "already a PNG" or "not an image or a video" before "can't be
    /// converted to MP4", which only says that the file is of another kind than that target.
    private nonisolated static func skipReason(_ file: SourceFile, _ targets: [any ConversionAction]) -> ConversionError {
        let refusals = targets.map { ConversionError.refusal(of: file, by: $0) }
        return refusals.first { if case .notApplicable = $0 { false } else { true } } ?? refusals[0]
    }
}
