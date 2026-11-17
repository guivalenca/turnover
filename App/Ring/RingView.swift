import AppKit
import RingModel

/// Draws the ring for a `RingModel`: a plain disc, each entry's format and estimate (with ✓ when
/// added, and a dot on the default JPEG quality), the added and highlighted entries' arcs, the
/// hub's text and the caption. #13 replaces this look with glass.
///
/// Flipped, so its angles match the model's: clockwise from the right, -90° at the top.
/// It never takes the drag or a click: hit-testing passes through to the panel's drop view.
@MainActor
final class RingView: NSView {
    /// The ring's centre, in this view's coordinates.
    var centre: NSPoint = .zero {
        didSet {
            setNeedsDisplay(ringRect(around: oldValue))
            setNeedsDisplay(captionRect(around: oldValue))
            setNeedsDisplay(ringRect(around: centre))
            setNeedsDisplay(captionRect(around: centre))
        }
    }

    /// What to draw. Only the ring's square is redrawn, and only when what it shows changes:
    /// the view covers the whole screen and the pointer updates it at the drag's rate.
    var model = RingModel() {
        didSet {
            guard oldValue.phase != model.phase || oldValue.entries != model.entries
                || oldValue.highlighted != model.highlighted || oldValue.hub != model.hub
                || oldValue.caption != model.caption else { return }
            setNeedsDisplay(ringRect(around: centre))
            setNeedsDisplay(captionRect(around: centre))
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

        for added in model.entries where added.isAdded {
            NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
            band(for: added).fill()
        }
        if let highlighted = model.highlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            band(for: highlighted).fill()
        }

        let hubDisc = NSBezierPath(ovalIn: circle(hub))
        NSColor.controlBackgroundColor.setFill()
        hubDisc.fill()
        NSColor.separatorColor.setStroke()
        hubDisc.stroke()

        for entry in model.entries {
            let radians = entry.angle * .pi / 180
            let at = NSPoint(x: centre.x + Self.labelRadius * cos(radians), y: centre.y + Self.labelRadius * sin(radians))
            let mark = entry.isAdded ? " ✓" : entry.isDefault ? " •" : ""
            drawLines(entry.title + mark, entry.subtitle, at: at, titleSize: 15)
        }
        if let text = model.hub {
            drawLines(text.title, text.detail, at: centre, titleSize: text.title.count > 6 ? 13 : 16)
        }
        if let caption = model.caption {
            let line = NSAttributedString(string: caption, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor,
            ])
            let size = line.size()
            let box = NSRect(x: centre.x - size.width / 2 - 10, y: centre.y + outer + 12,
                             width: size.width + 20, height: size.height + 8)
            NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
            NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
            line.draw(at: NSPoint(x: box.minX + 10, y: box.minY + 4))
        }
    }

    /// The band segment an entry owns, inset from its neighbours.
    private func band(for entry: RingModel.Entry) -> NSBezierPath {
        let gap: CGFloat = model.entries.count == 1 ? 0 : 3.5
        let band = NSBezierPath()
        band.appendArc(withCenter: centre, radius: Self.outerRadius - 8.5, startAngle: entry.arc.start + gap,
                       endAngle: entry.arc.end - gap, clockwise: false)
        band.appendArc(withCenter: centre, radius: Self.hubRadius + 9, startAngle: entry.arc.end - gap,
                       endAngle: entry.arc.start + gap, clockwise: true)
        band.close()
        return band
    }

    /// Where the caption goes, under the ring.
    private func captionRect(around point: NSPoint) -> NSRect {
        NSRect(x: point.x - 220, y: point.y + Self.outerRadius + 8, width: 440, height: 36)
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
