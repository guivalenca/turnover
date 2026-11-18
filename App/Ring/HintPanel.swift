import AppKit

/// A short message by the pointer, such as why a drag has nothing to convert. It ignores the
/// mouse, so the drag carries on to whatever is under it, and it fades after a moment.
@MainActor
final class HintPanel {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var fade: DispatchWorkItem?

    /// How long the hint stays before fading.
    private static let duration: TimeInterval = 2

    func show(_ text: String, near point: NSPoint) {
        let panel = self.panel ?? makePanel()
        label?.stringValue = text
        let size = label!.fittingSize
        let frame = NSRect(x: point.x + 18, y: point.y - 34 - size.height, width: size.width + 24, height: size.height + 12)
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        fade?.cancel()
        let fade = DispatchWorkItem { [weak self] in self?.hide() }
        self.fade = fade
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: fade)
    }

    func hide() {
        fade?.cancel()
        fade = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }

    private func makePanel() -> NSPanel {
        // Ignoring the mouse, so the drag carries on to whatever is under it.
        let panel = NSPanel.overlay(ignoresMouse: true, shadow: true)

        let background = NSVisualEffectView()
        background.material = .toolTip
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
        self.panel = panel
        self.label = label
        return panel
    }
}
