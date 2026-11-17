import AppKit
import TurnoverKit

/// Runs every conversion the app is asked for and selects the new files in Finder when a batch
/// ends. There is one for the app, so the runner's limits (at most two videos at a time) hold
/// across everything converting at once.
@MainActor
final class Conversions {
    /// Observe `runner.batches` for what is running now.
    let runner: JobRunner
    /// What `runner` converts with. The ring's estimates wait while it works.
    let converter = Converter()

    init() {
        runner = JobRunner(converter: converter)
    }

    /// A choice from the Finder menu. JPEG converts at the default quality from Settings.
    func convert(_ request: ConversionRequest) {
        log.notice("Converting \(request.files.count) file(s) to \(request.format.name, privacy: .public)")
        convert(request.files, to: [request.format.action(quality: Settings.jpegQuality)])
    }

    /// Converts each of `files` with the first of `actions` that takes it, for example PNG for
    /// the images and MP4 for the videos. Files none of them takes are skipped.
    @discardableResult
    func convert(_ files: [URL], to actions: [any ConversionAction]) -> Batch {
        let batch = runner.run(files, to: actions)
        Task { await finish(batch) }
        return batch
    }

    private func finish(_ batch: Batch) async {
        await batch.waitUntilFinished()
        for job in batch.jobs {
            switch job.state {
            case .converted(let result):
                log.notice("Converted \(result.source.path, privacy: .public) → \(result.output.path, privacy: .public)")
            case .failed(let reason):
                log.error("Failed: \(reason, privacy: .public)")
            case .skipped(let reason):
                log.notice("Skipped: \(reason.localizedDescription, privacy: .public)")
            case .cancelled, .waiting, .running:
                break
            }
        }
        if !batch.outputs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(batch.outputs)
        }
    }
}
