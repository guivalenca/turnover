import Foundation
import Observation

/// Runs batches of conversions. The app keeps one for everything it converts, so that its limits
/// hold across batches: images convert side by side, one per processor core, and videos at most
/// two at a time.
@MainActor @Observable
public final class JobRunner {
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
    @discardableResult
    public func run(_ files: [URL], to targets: [any ConversionAction]) -> Batch {
        precondition(!targets.isEmpty, "a batch needs at least one target")
        let batch = Batch(jobs: files.map(Job.init(source:)))
        Task {
            // One file at a time, so jobs start in the order given.
            for job in batch.jobs {
                let route = await Self.route(job.source, to: targets)
                guard !job.isFinished else { continue }  // cancelled meanwhile
                switch route {
                case .convert(let file, let action):
                    let lane: Lane = file.kind == .video ? .videos : .images
                    lanes[lane]!.queue.append(Queued(job: job, file: file, action: action))
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
            let state = await Self.convert(queued.file, with: queued.action, by: converter, progress: queued.job.report)
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
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    /// Why no target fits `file`: "already a PNG" or "not an image or a video" before "can't be
    /// converted to MP4", which only says that the file is of another kind than that target.
    private nonisolated static func skipReason(_ file: SourceFile, _ targets: [any ConversionAction]) -> ConversionError {
        let refusals = targets.map { Converter.refusal(of: file, by: $0) }
        return refusals.first { if case .notApplicable = $0 { false } else { true } } ?? refusals[0]
    }
}
