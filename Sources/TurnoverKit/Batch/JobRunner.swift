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
                return .skipped(skipReason(file, targets))
            }
            return .converted(try await converter.convert(source, with: action))
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
