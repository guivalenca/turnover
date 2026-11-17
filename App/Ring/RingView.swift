import AppKit
import RingModel

/// Draws the ring for a `RingModel`: a plain disc, each entry's format and estimate, the
/// highlighted entry's arc and the hub's text. #13 replaces this look with glass.
///
/// Flipped, so its angles match the model's: clockwise from the right, -90° at the top.
/// It never takes the drag or a click: hit-testing passes through to the panel's drop view.
@MainActor
final class RingView: NSView {
    /// The ring's centre, in this view's coordinates.
    var centre: NSPoint = .zero {
        didSet {
            setNeedsDisplay(ringRect(around: oldValue))
            setNeedsDisplay(ringRect(around: centre))
        }
    }

    /// What to draw. Only the ring's square is redrawn, and only when what it shows changes:
    /// the view covers the whole screen and the pointer updates it at the drag's rate.
    var model = RingModel() {
        didSet {
            guard oldValue.phase != model.phase || oldValue.entries != model.entries
                || oldValue.highlighted != model.highlighted || oldValue.hub != model.hub else { return }
            setNeedsDisplay(ringRect(around: centre))
        }
    }

    /// The prototype's proportions: the band's outer edge, where labels sit, and the hub.
    static let outerRadius: CGFloat = 128
    static let labelRadius: CGFloat = 87
    static let hubRadius: CGFloat = 42

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard model.phase == .open else { return }
        let outer = Self.outerRadius, hub = Self.hubRadius

        let disc = NSBezierPath(ovalIn: circle(outer))
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        disc.fill()
        NSColor.separatorColor.setStroke()
        disc.lineWidth = 1
        disc.stroke()

        if let highlighted = model.highlighted {
            let gap: CGFloat = model.entries.count == 1 ? 0 : 3.5
            let band = NSBezierPath()
            band.appendArc(withCenter: centre, radius: outer - 8.5, startAngle: highlighted.arc.start + gap,
                           endAngle: highlighted.arc.end - gap, clockwise: false)
            band.appendArc(withCenter: centre, radius: hub + 9, startAngle: highlighted.arc.end - gap,
                           endAngle: highlighted.arc.start + gap, clockwise: true)
            band.close()
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            band.fill()
        }

        let hubDisc = NSBezierPath(ovalIn: circle(hub))
        NSColor.controlBackgroundColor.setFill()
        hubDisc.fill()
        NSColor.separatorColor.setStroke()
        hubDisc.stroke()

        for entry in model.entries {
            let radians = entry.angle * .pi / 180
            let at = NSPoint(x: centre.x + Self.labelRadius * cos(radians), y: centre.y + Self.labelRadius * sin(radians))
            drawLines(entry.title, entry.subtitle, at: at, titleSize: 15)
        }
        if let text = model.hub {
            drawLines(text.title, text.detail, at: centre, titleSize: text.title.count > 6 ? 13 : 16)
        }
    }

    private func ringRect(around point: NSPoint) -> NSRect {
        let r = Self.outerRadius + 2
        return NSRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
    }

    private func circle(_ radius: CGFloat) -> NSRect {
        NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }

    /// A bold line over a smaller secondary one, centred on `point`.
    private func drawLines(_ title: String, _ detail: String, at point: NSPoint, titleSize: CGFloat) {
        let top = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: titleSize, weight: .semibold), .foregroundColor: NSColor.labelColor,
        ])
        let bottom = NSAttributedString(string: detail, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let a = top.size(), b = bottom.size()
        let y = point.y - (a.height + b.height) / 2
        top.draw(at: NSPoint(x: point.x - a.width / 2, y: y))
        bottom.draw(at: NSPoint(x: point.x - b.width / 2, y: y + a.height))
    }
}
