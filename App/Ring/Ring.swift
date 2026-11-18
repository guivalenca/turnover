import AppKit
import Observation
import os
import RingModel
import TurnoverKit
import TurnoverAppCore

/// The ring's log: `log stream --style compact --predicate 'subsystem == "com.guivalenca.turnover"'`.
let ringLog = Logger(subsystem: "com.guivalenca.turnover", category: "ring")

/// The drag + ⇧ ring: feeds what the drag watcher and the panels see to a `RingModel`, and acts
/// on what the model says (show or hide the ring, show a hint, convert). Every event goes to the
/// model with the time before it, and a timer sends the time again when a rest on a format is
/// due to add it.
///
/// An image dragged as a picture, out of a web page, has no file. When ⇧ first opens the ring
/// for it, its bytes are read from the drag pasteboard and staged as a temporary file
/// (`StagedImage`); from there the ring treats it as a drag of that one file, offered Original
/// too, and a drop saves it where the ring was dropped (`SaveDestination`).
@MainActor
final class Ring {
    private var model = RingModel(restDelay: Ring.restDelay())
    private let watcher = DragWatcher()
    private let panel = RingPanel()
    private let hint = HintPanel()
    private let conversions: Conversions
    private let estimator: Estimator

    /// Where the drag started, which decides what happens to the new files.
    private var source = DragSource.elsewhere
    /// The dragged files, once known, and their offers with the estimates refining.
    private var files: [URL]?
    private var live: LiveOffers?
    /// The image this drag carries as a picture, if it is such a drag.
    private var picture: Picture?

    /// An image dragged as a picture: what the pasteboard says it is, the process it was dragged
    /// from, and its file once it has been staged.
    private struct Picture {
        let id = UUID()
        let dragged: DraggedImage
        let source: pid_t?
        var isStaging = false
        var staged: StagedImage?
    }
    /// After the button goes up over the open ring: the panels' drop callbacks are still to
    /// come, and closing before them could lose the drop. This ends the drag if they never do.
    private var dropDeadline: DispatchWorkItem?
    /// Fires at the model's `rest?.deadline`, so a format is added while the pointer is still.
    private var restTimer: Timer?
    private var restTimerDeadline: TimeInterval?

    /// How long resting on a format takes to add it: the system's spring-loading delay (System
    /// Settings › Accessibility › Pointer Control), read at each drag so a change applies.
    static func restDelay() -> TimeInterval {
        let delay = UserDefaults.standard.object(forKey: "com.apple.springing.delay") as? Double
        return delay.map { min(max($0, 0.1), 3) } ?? 0.5
    }

    init(conversions: Conversions) {
        self.conversions = conversions
        estimator = Estimator(yieldingTo: conversions.converter)
    }

    func start() {
        panel.delegate = self
        watcher.onEvent = { [weak self] event in self?.handle(event) }
        watcher.start()
        #if DEBUG
        RingPreview.showIfAsked()
        #endif
    }

    private func handle(_ event: DragWatcher.Event) {
        switch event {
        case .dragStarted(let shiftDown, let optionDown, let files, let source):
            self.source = source
            picture = nil
            if let files {
                ringLog.notice("Drag started: \(files.count) file(s) read from the drag pasteboard at once")
            } else {
                ringLog.notice("Drag started: the drag pasteboard has file URLs but they can't be read yet")
            }
            if model.phase == .idle { model = RingModel(restDelay: Self.restDelay()) }
            send(.dragStarted(shiftDown: shiftDown))
            send(.option(down: optionDown))
            if let files { estimate(files) }
        case .imageDragStarted(let shiftDown, let optionDown, let image, let owner):
            source = .elsewhere
            picture = Picture(dragged: image, source: owner)
            panel.pictureThumbnail = nil
            ringLog.notice("Drag started: an image, \(image.contentType.identifier, privacy: .public), to be read when ⇧ opens the ring")
            if model.phase == .idle { model = RingModel(restDelay: Self.restDelay()) }
            send(.dragStarted(shiftDown: shiftDown))
            send(.option(down: optionDown))
        case .shift(let down):
            send(.shift(down: down))
        case .option(let down):
            send(.option(down: down))
        case .buttonUp:
            guard model.phase == .open else { return send(.dragEnded) }
            let deadline = DispatchWorkItem { [weak self] in
                ringLog.notice("No drop callback after the button went up; ending the drag")
                self?.send(.dragEnded)
            }
            dropDeadline = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: deadline)
        }
    }

    /// Feeds `event` to the model, after the time, then brings the screen and the conversions
    /// in line with it.
    private func send(_ event: RingModel.Event) {
        switch event {
        case .pointer, .offers, .time: break
        default: ringLog.debug("Event: \(String(describing: event), privacy: .public)")
        }
        let before = model
        model.send(.time(ProcessInfo.processInfo.systemUptime))
        model.send(event)

        if model.phase == .open, before.phase != .open {
            panel.open(at: NSEvent.mouseLocation,
                       pictureTypes: picture == nil ? [] : NSPasteboard(name: .drag).types ?? [])
            ringLog.notice("Ring opened with \(self.model.entries.map(\.title).joined(separator: ", "), privacy: .public)")
        } else if model.phase != .open, before.phase == .open {
            panel.close()
            ringLog.notice("Ring closed")
        }
        if model.highlighted?.title != before.highlighted?.title || model.hub != before.hub {
            ringLog.debug("Hub: \(self.model.hub?.text ?? "-", privacy: .public)")
        }
        if model.isFannedOut != before.isFannedOut {
            ringLog.notice("⌥: JPEG \(self.model.isFannedOut ? "fanned out" : "folded back", privacy: .public)")
        }
        if model.added != before.added, model.phase == .open {
            ringLog.notice("Added: \(self.model.caption ?? "-", privacy: .public)")
        }
        scheduleRestTimer()
        if model.phase == .open { panel.show(model) }

        if model.hint != before.hint {
            if let text = model.hint { hint.show(text, near: NSEvent.mouseLocation) } else { hint.hide() }
        }

        if let outcome = model.outcome, outcome != before.outcome {
            finish(outcome)
        }
        if model.phase == .idle, before.phase != .idle {
            dropDeadline?.cancel()
            dropDeadline = nil
            estimator.cancel()
            live = nil
            files = nil
            // A staged image that wasn't dropped on an entry is of no more use. One still being
            // staged removes itself when it finds the drag gone.
            picture?.staged?.remove()
            picture = nil
            panel.pictureThumbnail = nil
        }
        if model.phase == .open { stagePicture() }
    }

    /// The first time the ring is open for an image dragged as a picture: reads its bytes from
    /// the drag pasteboard, where the browser put them, and stages them as a file. The offers
    /// follow as for a drag of that file, with Original; until then the ring is empty.
    ///
    /// Not before ⇧: most image drags never open the ring, and their bytes are none of
    /// Turnover's business.
    private func stagePicture() {
        guard var picture, !picture.isStaging, picture.staged == nil else { return }
        picture.isStaging = true
        self.picture = picture
        let (id, name) = (picture.id, picture.dragged.fileName)
        let data = NSPasteboard(name: .drag).data(forType: .init(picture.dragged.pasteboardType))
        Task {
            do {
                guard let data, !data.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
                let staged = try await StagedImage.write(data, named: name)
                guard self.picture?.id == id else { return staged.remove() }  // the drag ended meanwhile
                self.picture?.staged = staged
                ringLog.notice("Staged the dragged image: \(data.count) bytes as \(name, privacy: .public)")
                estimate([staged.file], keepingOriginal: true)
                let thumbnail = await staged.thumbnail(side: RingPanel.dragImageSide)
                if self.picture?.id == id { panel.pictureThumbnail = thumbnail }
            } catch {
                ringLog.error("Couldn't read the dragged image from the drag pasteboard: \(error.localizedDescription, privacy: .public)")
                guard self.picture?.id == id else { return }
                // A hint instead of the ring, as for a file that can't be read.
                send(.offers(Offers(groups: [], skipped: [.unreadable(URL(fileURLWithPath: name))])))
            }
        }
    }

    /// Keeps the rest timer on the model's rest deadline: it sends the time then, and the model
    /// adds the format if the pointer is still on it.
    private func scheduleRestTimer() {
        let deadline = model.rest?.deadline
        guard deadline != restTimerDeadline else { return }
        restTimer?.invalidate()
        restTimer = nil
        restTimerDeadline = deadline
        guard let deadline else { return }
        let timer = Timer(timeInterval: max(0, deadline - ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.restTimer = nil
                self.restTimerDeadline = nil
                self.send(.time(ProcessInfo.processInfo.systemUptime))
            }
        }
        // The common modes, so it fires while AppKit tracks the drag over the panel.
        RunLoop.main.add(timer, forMode: .common)
        restTimer = timer
    }

    private func finish(_ outcome: RingModel.Outcome) {
        switch outcome {
        case .convert(let choices):
            let summary = choices.map { "\($0.files.count) to \($0.format.name)\($0.quality.map { " \($0.percent)%" } ?? "")" }
            if let staged = picture?.staged {
                // The conversion owns the staged file from here, and removes it when it is done.
                picture?.staged = nil
                let point = NSEvent.mouseLocation
                let destination = SaveDestination.current(droppedAt: point, draggedFrom: picture?.source)
                ringLog.notice("Ring drop: an image, \(summary.joined(separator: ", "), privacy: .public), saved to \(String(describing: destination), privacy: .public)")
                conversions.save(staged, as: choices.map(\.action), to: destination, droppedAt: point)
                return
            }
            let origin = source.origin(drop: DesktopCoordinates.current.topLeft(NSEvent.mouseLocation))
            ringLog.notice("Ring drop: \(summary.joined(separator: ", "), privacy: .public), from \(String(describing: origin), privacy: .public)")
            conversions.convert(choices.flatMap(\.files), to: choices.map(\.action), origin: origin)
        case .cancel:
            ringLog.notice("Ring cancelled; nothing converted")
        }
    }

    /// Starts working out the offers for `files` and feeds them, and every refinement of their
    /// estimates, to the model. The files are looked at off the main actor, so the drag never
    /// waits for them.
    private func estimate(_ files: [URL], keepingOriginal: Bool = false) {
        guard files != self.files else { return }
        self.files = files
        let quality = AppSettings().jpegQuality
        Task {
            let live = await estimator.estimate(files, jpegQuality: quality, keepingOriginal: keepingOriginal)
            guard files == self.files else { return }  // the drag ended, or other files came
            self.live = live
            follow(live)
        }
    }

    private func follow(_ live: LiveOffers) {
        guard live === self.live else { return }
        let offers = withObservationTracking { live.offers } onChange: { [weak self] in
            Task { @MainActor in self?.follow(live) }
        }
        send(.offers(offers))
    }
}

extension Ring: RingPanelDelegate {
    func ringPanel(_ panel: RingPanel, draggingFiles files: [URL]) {
        // The drag pasteboard couldn't be read at drag start: the files come from the drag now.
        guard self.files == nil else { return }
        ringLog.notice("Files from the panel's draggingEntered: \(files.count)")
        // Read without the files, a drag that didn't start in a Finder window was "elsewhere";
        // with them, it is the Desktop's if they are all on it.
        if source == .elsewhere,
           ConversionOrigin(menuFiles: files, desktopFolder: FinderDesktop.folder) == .desktop(drop: nil) {
            source = .desktop
        }
        estimate(files)
    }

    func ringPanel(_ panel: RingPanel, pointerAt point: NSPoint) -> Bool {
        // The model's y grows downwards, like its angles.
        send(.pointer(x: point.x - panel.centre.x, y: panel.centre.y - point.y))
        return model.highlighted != nil
    }

    func ringPanelDrop(_ panel: RingPanel) -> Bool {
        send(.drop)
        if case .convert = model.outcome { return true }
        return false
    }

    func ringPanel(_ panel: RingPanel, dragLeftWithButtonDown buttonDown: Bool) {
        // With the button still down, the system cancelled the drag: Esc.
        send(buttonDown ? .escape : .dragEnded)
    }
}
