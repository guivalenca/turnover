import AppKit
import Observation
import os
import RingModel
import TurnoverKit

/// The ring's log: `log stream --style compact --predicate 'subsystem == "com.guivalenca.turnover"'`.
let ringLog = Logger(subsystem: "com.guivalenca.turnover", category: "ring")

/// The drag + ⇧ ring: feeds what the drag watcher and the panels see to a `RingModel`, and acts
/// on what the model says (show or hide the ring, show a hint, convert). Every event goes to the
/// model with the time before it, and a timer sends the time again when a rest on a format is
/// due to add it.
@MainActor
final class Ring {
    private var model = RingModel(restDelay: Ring.restDelay())
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
        case .dragStarted(let shiftDown, let optionDown, let files):
            if let files {
                ringLog.notice("Drag started: \(files.count) file(s) read from the drag pasteboard at once")
            } else {
                ringLog.notice("Drag started: the drag pasteboard has file URLs but they can't be read yet")
            }
            if model.phase == .idle { model = RingModel(restDelay: Self.restDelay()) }
            send(.dragStarted(shiftDown: shiftDown))
            send(.option(down: optionDown))
            if let files { estimate(files) }
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
            panel.open(at: NSEvent.mouseLocation)
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
            ringLog.notice("Ring drop: \(summary.joined(separator: ", "), privacy: .public)")
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
        let live = estimator.estimate(files, jpegQuality: AppSettings().jpegQuality)
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
