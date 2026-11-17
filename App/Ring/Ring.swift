import AppKit
import Observation
import os
import RingModel
import TurnoverKit

/// The ring's log: `log stream --style compact --predicate 'subsystem == "com.guivalenca.turnover"'`.
let ringLog = Logger(subsystem: "com.guivalenca.turnover", category: "ring")

/// The drag + ⇧ ring: feeds what the drag watcher and the panels see to a `RingModel`, and acts
/// on what the model says (show or hide the ring, show a hint, convert).
@MainActor
final class Ring {
    private var model = RingModel()
    private let watcher = DragWatcher()
    private let panel = RingPanel()
    private let hint = HintPanel()
    private let conversions: Conversions
    private let estimator: Estimator

    /// The dragged files, once known, and their offers with the estimates refining.
    private var files: [URL]?
    private var live: LiveOffers?
    /// After the button goes up over the open ring: the panels' drop callbacks are still to
    /// come, and closing before them could lose the drop. This ends the drag if they never do.
    private var dropDeadline: DispatchWorkItem?

    init(conversions: Conversions) {
        self.conversions = conversions
        estimator = Estimator(yieldingTo: conversions.converter)
    }

    func start() {
        panel.delegate = self
        watcher.onEvent = { [weak self] event in self?.handle(event) }
        watcher.start()
    }

    private func handle(_ event: DragWatcher.Event) {
        switch event {
        case .dragStarted(let shiftDown, let files):
            if let files {
                ringLog.notice("Drag started: \(files.count) file(s) read from the drag pasteboard at once")
            } else {
                ringLog.notice("Drag started: the drag pasteboard has file URLs but they can't be read yet")
            }
            send(.dragStarted(shiftDown: shiftDown))
            if let files { estimate(files) }
        case .shift(let down):
            send(.shift(down: down))
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

    /// Feeds `event` to the model, then brings the screen and the conversions in line with it.
    private func send(_ event: RingModel.Event) {
        switch event {
        case .pointer, .offers: break
        default: ringLog.debug("Event: \(String(describing: event), privacy: .public)")
        }
        let before = model
        model.send(event)

        if model.phase == .open, before.phase != .open {
            panel.open(at: NSEvent.mouseLocation)
            ringLog.notice("Ring opened with \(self.model.entries.map(\.title).joined(separator: ", "), privacy: .public)")
        } else if model.phase != .open, before.phase == .open {
            panel.close()
            ringLog.notice("Ring closed")
        }
        if model.highlighted?.title != before.highlighted?.title || model.hub != before.hub {
            ringLog.debug("Hub: \(self.model.hub?.text ?? "-", privacy: .public)")
        }
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
        }
    }

    private func finish(_ outcome: RingModel.Outcome) {
        switch outcome {
        case .convert(let choices):
            ringLog.notice("Ring drop: \(choices.map { "\($0.files.count) to \($0.format.name)" }.joined(separator: ", "), privacy: .public)")
            conversions.convert(choices.flatMap(\.files), to: choices.map(\.action))
        case .cancel:
            ringLog.notice("Ring cancelled; nothing converted")
        }
    }

    /// Starts working out the offers for `files` and feeds them, and every refinement of their
    /// estimates, to the model.
    private func estimate(_ files: [URL]) {
        guard files != self.files else { return }
        self.files = files
        let live = estimator.estimate(files, jpegQuality: Settings.jpegQuality)
        self.live = live
        follow(live)
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
