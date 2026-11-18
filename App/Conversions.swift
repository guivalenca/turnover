import AppKit
import TurnoverKit
import TurnoverAppCore

/// Runs every conversion the app is asked for, then deals with the new files as where it
/// started says (#18): selected in a Finder window, put where the ring was dropped on the
/// Desktop, or left alone. A conversion that didn't start in a Finder window never opens one.
/// There is one for the app, so the runner's limits (at most two videos at a time) hold across
/// everything converting at once.
///
/// Every batch gets the same feedback, whoever started it: the menu bar item while it is slow,
/// and notifications when it was slow, failed or saved to Downloads.
@MainActor
final class Conversions {
    /// Observe `runner.batches` for what is running now.
    let runner: JobRunner
    /// What `runner` converts with. The ring's estimates wait while it works.
    let converter = Converter()
    /// What the menu bar item and notifications say about the batches.
    let feedback: Feedback
    private let notifier: Notifier
    private let statusItem: StatusItem
    private let desktop = FinderDesktop()

    init() {
        runner = JobRunner(converter: converter)
        let notifier = Notifier()
        self.notifier = notifier
        feedback = Feedback(notify: notifier.post)
        statusItem = StatusItem(feedback: feedback)
    }

    /// A choice from the Finder menu. JPEG converts at the default quality from `AppSettings`.
    func convert(_ request: ConversionRequest) {
        let origin = ConversionOrigin(menuFiles: request.files, desktopFolder: FinderDesktop.folder)
        log.notice("Converting \(request.files.count) file(s) to \(request.format.name, privacy: .public), from \(String(describing: origin), privacy: .public)")
        convert(request.files, to: [request.format.action(quality: AppSettings().jpegQuality)], origin: origin)
    }

    /// Converts each of `files` with the first of `actions` that takes it, for example PNG for
    /// the images and MP4 for the videos. Files none of them takes are skipped.
    @discardableResult
    func convert(_ files: [URL], to actions: [any ConversionAction], origin: ConversionOrigin) -> Batch {
        let batch = runner.run(files, to: actions)
        feedback.track(batch)
        let handling = origin.handling
        if case .placeOnDesktop(let drop) = handling { desktop.place(batch, from: drop) }
        Task { await finish(batch, selecting: handling == .selectInFinder) }
        return batch
    }

    private func finish(_ batch: Batch, selecting: Bool) async {
        await batch.waitUntilFinished()
        for job in batch.jobs {
            switch job.state {
            case .converted(let result):
                log.notice("Converted \(result.source.path, privacy: .public) → \(result.output.path, privacy: .public)")
            case .failed(let reason):
                log.error("Failed: \(reason.localizedDescription, privacy: .public)")
            case .skipped(let reason):
                log.notice("Skipped: \(reason.localizedDescription, privacy: .public)")
            case .cancelled, .waiting, .running:
                break
            }
        }
        if selecting, !batch.outputs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(batch.outputs)
        }
    }
}
