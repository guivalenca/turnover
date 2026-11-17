import Foundation
import Observation

/// Runs batches of conversions. The app keeps one for everything it converts.
@MainActor @Observable
public final class JobRunner {
    @ObservationIgnored private let converter: Converter

    public init(converter: Converter = Converter()) {
        self.converter = converter
    }

    /// Starts converting `files` and returns at once. Each file is converted by the first of
    /// `targets` that accepts it, for example PNG for the images and MP4 for the videos.
    @discardableResult
    public func run(_ files: [URL], to targets: [any ConversionAction]) -> Batch {
        let batch = Batch(jobs: files.map(Job.init(source:)))
        let converter = converter
        Task {
            for job in batch.jobs {
                job.state = .running
                job.state = await Self.convert(job.source, to: targets, with: converter)
                batch.jobEnded()
            }
        }
        return batch
    }

    private nonisolated static func convert(
        _ source: URL, to targets: [any ConversionAction], with converter: Converter
    ) async -> Job.State {
        do {
            let file = try SourceFile(source)
            guard let action = targets.first(where: { $0.accepts(file) }) else {
                return .failed(reason: "\(source.lastPathComponent): no target")
            }
            return .converted(try await converter.convert(source, with: action))
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }
}
