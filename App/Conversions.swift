import AppKit
import TurnoverKit
import TurnoverAppCore

/// Runs every conversion the app is asked for, then deals with the new files as where it
/// started says (#18): selected in a Finder window, put where the ring was dropped on the
/// Desktop, or left alone. A conversion that didn't start in a Finder window never opens one.
/// There is one for the app, so the runner's limits (at most two videos at a time) hold across
/// everything converting at once.
///
/// An image dragged out of a web page has no folder: it is saved where its ring was dropped
/// (`save`), on the Desktop, in a Finder window's folder, or in Downloads.
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
    /// Says where an image dragged out of a web page was saved, where its ring was.
    private let saved = HintPanel()

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

    // MARK: Images dragged out of a web page

    /// Saves `image`, staged from a drag out of a web page, with the first of `actions` that
    /// takes it (PNG, JPEG or Original), where the ring was dropped at `point` (AppKit screen
    /// coordinates) says:
    ///
    /// - On the Desktop: there, at that spot, as for a drag of Desktop files.
    /// - Over a Finder window: in its folder, selected. Finder is asked which folder; if it
    ///   won't say, or the folder can't be written to, Downloads.
    /// - Anywhere else: in Downloads, which a short note by the pointer says, and the Dock's
    ///   Downloads stack shows. Over another app than the one it came from, the new file is put
    ///   on the clipboard too, ready to paste there.
    ///
    /// The staged file is removed once the batch has ended.
    func save(_ image: StagedImage, as actions: [any ConversionAction], to destination: SaveDestination,
              droppedAt point: NSPoint) {
        Task {
            defer { image.remove() }
            var folder = converter.downloads
            switch destination {
            case .desktop:
                folder = FinderDesktop.folder
            case .finderWindow(let drop, let frame):
                if let shown = await FinderWindows.folder(at: drop, inWindow: frame),
                   FileManager.default.isWritableFile(atPath: shown.path) {
                    folder = shown
                }
            case .downloads:
                break
            }
            log.notice("Saving the dragged image \(image.file.lastPathComponent, privacy: .public) into \(folder.path, privacy: .public)")
            let batch = runner.run([image.file], to: actions, into: folder)
            feedback.track(batch)
            if case .desktop(let drop) = destination { desktop.place(batch, from: drop) }
            await finish(batch, selecting: false)

            let outputs = batch.outputs
            guard !outputs.isEmpty else { return }  // it failed: the notification says why
            if folder == converter.downloads {
                let copied = destination == .downloads(copied: true)
                if copied {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects(outputs.map { $0 as NSURL })
                }
                log.notice("Saved to Downloads\(copied ? ", and copied to the clipboard" : "", privacy: .public): \(outputs.map(\.lastPathComponent).joined(separator: ", "), privacy: .public)")
                saved.show(copied
                    ? String(localized: "Saved to Downloads · Copied",
                             comment: "A short note by the pointer: an image dragged out of a web page was saved to Downloads and put on the clipboard, ready to paste.")
                    : String(localized: "Saved to Downloads",
                             comment: "A short note by the pointer: an image dragged out of a web page was saved to Downloads."),
                    near: point)
                // What browsers post for a finished download: the Dock's Downloads stack bounces.
                for output in outputs {
                    DistributedNotificationCenter.default().postNotificationName(
                        .init("com.apple.DownloadFileFinished"), object: output.path, userInfo: nil, deliverImmediately: true)
                }
            } else if case .finderWindow = destination {
                NSWorkspace.shared.activateFileViewerSelecting(outputs)
            }
        }
    }
}
