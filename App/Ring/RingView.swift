import AppKit
import QuartzCore
import RingModel

/// The glass ring, drawing a `RingLook`:
/// - a disc of glass (the band) holding the tinted highlight, the tints of added entries and
///   each entry's format over its estimate;
/// - a glass lens in the middle (the hub) previewing what a drop converts;
/// - for mixed drags, a glass caption under the disc.
///
/// The highlight is a sector of accent-tinted glass that springs round to the highlighted entry,
/// the shorter way. With Reduce Motion it moves at once and fades in instead.
///
/// It sits in its own window (`RingWindow`), which ignores the mouse: the panels under it catch
/// the drag. Its own coordinates are AppKit's, y up; the look's angles are the model's
/// (clockwise from the right), so they are turned round where they are drawn.
@MainActor
final class RingView: NSView {
    /// The prototype's proportions.
    nonisolated static let outerRadius: CGFloat = 128
    nonisolated static let labelRadius: CGFloat = 87
    nonisolated static let hubRadius: CGFloat = 42
    /// The window's size, with the ring's centre in its middle.
    nonisolated static let size = NSSize(width: 400, height: 400)
    /// What the ring draws around its centre (y up): the disc, and the caption under it, at its
    /// widest. Kept on screen when the ring opens near an edge.
    nonisolated static let drawing = CGRect(x: -Caption.maxWidth / 2, y: -(Caption.top + Caption.height + 8),
                                width: Caption.maxWidth, height: Caption.top + Caption.height + 8 + outerRadius + 8)

    /// The highlight: a sector from just outside the hub to just inside the edge, its corners
    /// rounded by a stroke, with a little gap to the next entry's.
    private enum Sector {
        static let inner: CGFloat = RingView.hubRadius + 9
        static let outer: CGFloat = RingView.outerRadius - 8.5
        static let rounding: CGFloat = 9
        static let gap = 3.5
    }

    private enum Caption {
        /// From the ring's centre down to the caption's top.
        static let top: CGFloat = RingView.outerRadius + 16
        static let height: CGFloat = 24
        static let maxWidth: CGFloat = 320
    }

    /// Room for an entry's label: inside the band, clear of the hub lens.
    private static let labelBand: ClosedRange<CGFloat> = (hubRadius + 5)...(outerRadius - 4)

    var look = RingLook() {
        didSet { if look != oldValue { update(from: oldValue) } }
    }

    /// The pointer's angle on the ring (the model's degrees), so a half turn goes its way.
    var pointerAngle: Double?

    private let centre = CGPoint(x: RingView.size.width / 2, y: RingView.size.height / 2)
    private var band: NSView!
    private let bandContent = NSView()
    private let tints = NSView()
    private var hub: NSView!
    private let hubContent = NSView()
    private let hubTitle = NSTextField(labelWithString: "")
    private let hubDetail = NSTextField(labelWithString: "")
    private var captionSurface: NSView!
    private let captionLabel = NSTextField(labelWithString: "")
    private var labels: [EntryLabel] = []

    /// The highlight's layers: `turner` turns; `body` tints the glass (plainly, so it shows over
    /// white too), `hue` gives the glass under it the accent's hue (Liquid Glass only), and
    /// `sheen` is the light on it.
    private let turner = CALayer()
    private let body = CAShapeLayer()
    private let hue = CAShapeLayer()
    private let sheen = CAGradientLayer()
    private let sheenMask = CAShapeLayer()
    /// Tints for the added entries.
    private let addedTints = CALayer()
    /// The highlight's angle as drawn, counting past whole turns; nil before the first highlight.
    private var turnedTo: Double?
    private var turns = 0

    override init(frame: NSRect) {
        super.init(frame: NSRect(origin: frame.origin, size: Self.size))
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Building

    private func build() {
        let r = Self.outerRadius
        let disc = NSRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)

        bandContent.wantsLayer = true
        tints.wantsLayer = true
        tints.frame = NSRect(origin: .zero, size: disc.size)
        tints.autoresizingMask = [.width, .height]
        bandContent.addSubview(tints)
        let tintLayer = tints.layer!
        addedTints.frame = tints.bounds
        tintLayer.addSublayer(addedTints)
        turner.frame = tints.bounds
        turner.opacity = 0
        tintLayer.addSublayer(turner)
        for shape in [body, hue, sheenMask] {
            shape.frame = tints.bounds
            shape.lineWidth = Sector.rounding
            shape.lineJoin = .round
        }
        turner.addSublayer(body)
        if RingMaterial.usesGlass {
            hue.compositingFilter = "colorBlendMode"
            turner.addSublayer(hue)
        }
        sheen.frame = tints.bounds
        sheen.type = .radial
        sheen.startPoint = CGPoint(x: 0.5, y: 0.5)
        sheen.endPoint = CGPoint(x: 1, y: 1)
        sheen.locations = [0, 0.6, 1]
        sheenMask.strokeColor = NSColor.black.cgColor
        sheenMask.fillColor = NSColor.black.cgColor
        sheen.mask = sheenMask
        turner.addSublayer(sheen)

        band = RingMaterial.surface(frame: disc, cornerRadius: r, content: bandContent)

        let h = Self.hubRadius
        hubContent.wantsLayer = true
        for field in [hubTitle, hubDetail] {
            field.alignment = .center
            field.lineBreakMode = .byTruncatingTail
            hubContent.addSubview(field)
        }
        hub = RingMaterial.surface(frame: NSRect(x: centre.x - h, y: centre.y - h, width: 2 * h, height: 2 * h),
                                   cornerRadius: h, content: hubContent, lens: true)

        let captionContent = NSView()
        captionLabel.font = .systemFont(ofSize: 11.5)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.alignment = .center
        captionLabel.lineBreakMode = .byTruncatingTail
        captionContent.addSubview(captionLabel)
        captionSurface = RingMaterial.surface(frame: .zero, cornerRadius: Caption.height / 2, content: captionContent)
        captionSurface.isHidden = true

        // Not in a glass container: it would merge the hub lens into the band.
        addSubview(band)
        addSubview(hub)
        addSubview(captionSurface)
        applyColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    /// How strongly the highlight tints the glass. Added entries are tinted more lightly.
    private var tint: Float {
        RingMaterial.usesGlass ? (isDark ? 0.3 : 0.2) : (isDark ? 0.42 : 0.3)
    }

    /// How strongly the highlight turns the glass under it the accent's hue (Liquid Glass only).
    private var hueStrength: Float { isDark ? 0.45 : 0.35 }

    /// Layer colours don't follow the appearance by themselves.
    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor.controlAccentColor.cgColor
            for shape in [body, hue] + ((addedTints.sublayers ?? []).compactMap { $0 as? CAShapeLayer }) {
                shape.fillColor = accent
                shape.strokeColor = accent
            }
            sheen.colors = [NSColor(white: 1, alpha: 0).cgColor, NSColor(white: 1, alpha: 0).cgColor,
                            NSColor(white: 1, alpha: isDark ? 0.14 : 0.3).cgColor]
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.opacity = tint
        hue.opacity = hueStrength
        for layer in addedTints.sublayers ?? [] { layer.opacity = tint * 0.7 }
        CATransaction.commit()
    }

    // MARK: - Updating

    private func update(from old: RingLook) {
        let relaid = !look.hasSameLayout(as: old) || labels.count != look.entries.count
        if relaid { layOutLabels() }
        let reduceMotion = RingMotion.isReduced
        for (index, label) in labels.enumerated() {
            label.show(look.entries[index], highlighted: index == look.highlighted,
                       maxWidth: labelWidth(index), reduceMotion: reduceMotion)
            // New labels (the ring's first, or ⌥ fanning JPEG out) pop in one after another.
            if relaid { label.pop(after: Double(index) * 0.035, reduceMotion: reduceMotion) }
        }
        if look.entries.filter(\.isAdded) != old.entries.filter(\.isAdded) || relaid { updateAddedTints() }
        updateHighlight(from: old)
        updateHub(from: old)
        updateCaption()
    }

    private func layOutLabels() {
        labels.forEach { $0.removeFromSuperview() }
        labels = look.entries.map { _ in EntryLabel() }
        let local = CGPoint(x: Self.outerRadius, y: Self.outerRadius)
        for (index, label) in labels.enumerated() {
            label.centre = point(Self.labelRadius, look.entries[index].angle, around: local)
            bandContent.addSubview(label)
        }
    }

    /// The angle to the nearest neighbour, so the label leaves it room.
    private func labelWidth(_ index: Int) -> CGFloat {
        let entry = look.entries[index]
        let spacing = look.entries.count > 1 ? 2 * min(entry.angle - entry.arcStart, entry.arcEnd - entry.angle) : nil
        return RingGeometry.labelWidth(at: entry.angle, spacing: spacing, height: 30, radius: Self.labelRadius,
                                       band: Self.labelBand)
    }

    private func updateAddedTints() {
        let added = look.entries.filter(\.isAdded)
        let layers = addedTints.sublayers ?? []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, entry) in added.enumerated() {
            let shape: CAShapeLayer
            if index < layers.count, let existing = layers[index] as? CAShapeLayer {
                shape = existing
            } else {
                shape = CAShapeLayer()
                shape.frame = addedTints.bounds
                shape.lineWidth = Sector.rounding
                shape.lineJoin = .round
                addedTints.addSublayer(shape)
            }
            shape.path = sector(entry, around: entry.angle)
        }
        for layer in layers.dropFirst(added.count) { layer.removeFromSuperlayer() }
        CATransaction.commit()
        applyColors()
    }

    private func updateHighlight(from old: RingLook) {
        let reduceMotion = RingMotion.isReduced
        guard let index = look.highlighted else {
            if old.highlighted != nil { fade(turner, to: 0, duration: 0.15) }
            stopResting()
            return
        }
        let entry = look.entries[index]
        let changed = old.highlighted != index || !look.hasSameLayout(as: old)
        if changed {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Its shape is the entry's arc, drawn at 0° and turned into place.
            body.path = sector(entry, around: 0)
            hue.path = body.path
            sheenMask.path = body.path
            CATransaction.commit()

            if let from = turnedTo {
                // From wherever it last was, even after a moment on the hub, as the prototype does.
                let to = RingGeometry.turn(to: entry.angle, from: from, passing: pointerAngle)
                turn(from: from, to: to, animated: !reduceMotion)
                turnedTo = to
            } else {
                turn(from: entry.angle, to: entry.angle, animated: false)
                turnedTo = entry.angle
            }
            if old.highlighted == nil || reduceMotion {
                fade(turner, to: 1, duration: old.highlighted == nil ? 0.15 : 0.12, from: reduceMotion ? 0.3 : nil)
            }
        }
        // Resting on it (a mixed ring): the tint fills until the entry is added, then blinks.
        if let rest = look.restingFor, changed || old.restingFor == nil {
            startResting(for: rest)
        } else if look.restingFor == nil, old.restingFor != nil {
            stopResting()
        }
        if entry.isAdded, old.highlighted == index, old.entries.indices.contains(index), !old.entries[index].isAdded {
            blink()
        }
    }

    /// Turns the highlight from `from` to `to` (model degrees, y down), with a spring.
    private func turn(from: Double, to: Double, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        turner.transform = CATransform3DMakeRotation(-to * .pi / 180, 0, 0, 1)
        CATransaction.commit()
        guard animated, from != to else { return }
        // Additive, so a new turn starts from wherever the last one has got to, and blends in.
        let spring = CASpringAnimation(perceptualDuration: 0.42, bounce: 0.22)
        spring.keyPath = "transform.rotation.z"
        spring.isAdditive = true
        spring.fromValue = (to - from) * .pi / 180
        spring.toValue = 0
        spring.duration = spring.settlingDuration
        turns += 1
        turner.add(spring, forKey: "turn \(turns)")
    }

    private func startResting(for duration: TimeInterval) {
        let fill = CABasicAnimation(keyPath: "opacity")
        fill.fromValue = tint
        fill.toValue = min(1, tint * 2.4)
        fill.duration = duration
        fill.fillMode = .forwards
        fill.isRemovedOnCompletion = false
        body.add(fill, forKey: "rest")
    }

    private func stopResting() {
        body.removeAnimation(forKey: "rest")
    }

    /// The entry under the pointer was just added: the highlight blinks twice.
    private func blink() {
        stopResting()
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 0.2, 1, 0.2, 1]
        blink.duration = 0.64
        turner.add(blink, forKey: "blink")
    }

    private func updateHub(from old: RingLook) {
        guard look.hub != old.hub else { return }
        if old.hub != nil {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.12
            hubContent.layer?.add(fade, forKey: "text")
        }
        let title = look.hub?.title ?? "", detail = look.hub?.detail ?? ""
        // A count reads large; a format a little smaller; two formats smaller still.
        let size: CGFloat = title.allSatisfy(\.isNumber) ? 21 : title.count <= 6 ? 16 : 13
        // As wide as the lens is where each line sits, less a margin.
        let width = 2 * Self.hubRadius - 8
        fit(hubTitle, NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor.labelColor,
        ]), maxWidth: width)
        fit(hubDetail, NSAttributedString(string: detail, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]), maxWidth: width)
        let h = Self.hubRadius
        let a = hubTitle.frame.height, b = hubDetail.frame.height
        let top = h + (a + b) / 2
        hubTitle.setFrameOrigin(NSPoint(x: h - hubTitle.frame.width / 2, y: top - a))
        hubDetail.setFrameOrigin(NSPoint(x: h - hubDetail.frame.width / 2, y: top - a - b))
    }

    private func updateCaption() {
        guard let text = look.caption else {
            captionSurface.isHidden = true
            return
        }
        let wasHidden = captionSurface.isHidden
        fit(captionLabel, NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: NSColor.secondaryLabelColor,
        ]), maxWidth: Caption.maxWidth - 22)
        let size = NSSize(width: captionLabel.frame.width + 22, height: Caption.height)
        captionSurface.frame = NSRect(x: centre.x - size.width / 2, y: centre.y - Caption.top - size.height,
                                      width: size.width, height: size.height)
        captionLabel.setFrameOrigin(NSPoint(x: 11, y: (size.height - captionLabel.frame.height) / 2))
        captionSurface.isHidden = false
        if wasHidden, let layer = captionSurface.layer { fade(layer, to: 1, duration: 0.2, from: 0) }
    }

    // MARK: - Appearing

    /// The ring grows into place with a spring as its window fades in (its labels pop in as they
    /// arrive). With Reduce Motion, it only fades.
    func appear() {
        guard let layer else { return }
        let reduceMotion = RingMotion.isReduced
        layer.sublayerTransform = CATransform3DIdentity
        if !reduceMotion {
            let grow = CASpringAnimation(perceptualDuration: 0.34, bounce: 0.25)
            grow.keyPath = "sublayerTransform"
            grow.fromValue = scale(0.82)
            grow.toValue = CATransform3DIdentity
            grow.duration = grow.settlingDuration
            layer.add(grow, forKey: "appear")
        }
    }

    /// `factor` about the ring's centre, for `sublayerTransform`.
    private func scale(_ factor: CGFloat) -> CATransform3D {
        var transform = CATransform3DMakeTranslation(centre.x, centre.y, 0)
        transform = CATransform3DScale(transform, factor, factor, 1)
        return CATransform3DTranslate(transform, -centre.x, -centre.y, 0)
    }

    /// Back to nothing, ready for the next drag.
    func reset() {
        look = RingLook()
        turnedTo = nil
        turner.removeAllAnimations()
        body.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        turner.opacity = 0
        CATransaction.commit()
        applyColors()
    }

    // MARK: - Drawing helpers

    /// `radius` from `centre` at `angle` (the model's degrees, y down), in y-up coordinates.
    private func point(_ radius: CGFloat, _ angle: Double, around centre: CGPoint) -> CGPoint {
        CGPoint(x: centre.x + radius * cos(angle * .pi / 180), y: centre.y - radius * sin(angle * .pi / 180))
    }

    /// The highlight's shape for `entry`'s arc, drawn as if the entry sat at `angle`.
    private func sector(_ entry: RingLook.Entry, around angle: Double) -> CGPath {
        let c = CGPoint(x: Self.outerRadius, y: Self.outerRadius)
        let path = CGMutablePath()
        let sweep = entry.arcEnd - entry.arcStart
        if sweep >= 359.9 {
            // A lone entry owns the whole ring.
            path.addEllipse(in: CGRect(x: c.x - Sector.outer, y: c.y - Sector.outer,
                                       width: 2 * Sector.outer, height: 2 * Sector.outer))
            path.addEllipse(in: CGRect(x: c.x - Sector.inner, y: c.y - Sector.inner,
                                       width: 2 * Sector.inner, height: 2 * Sector.inner))
            return path
        }
        let start = angle + (entry.arcStart - entry.angle) + Sector.gap
        let end = angle + (entry.arcEnd - entry.angle) - Sector.gap
        let radians = { (degrees: Double) in CGFloat(-degrees * .pi / 180) }
        path.addArc(center: c, radius: Sector.outer, startAngle: radians(start), endAngle: radians(end), clockwise: true)
        path.addArc(center: c, radius: Sector.inner, startAngle: radians(end), endAngle: radians(start), clockwise: false)
        path.closeSubpath()
        return path
    }

    private func fade(_ layer: CALayer, to opacity: Float, duration: TimeInterval, from start: Float? = nil) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = start ?? layer.presentation()?.opacity ?? layer.opacity
        fade.toValue = opacity
        fade.duration = duration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        CATransaction.commit()
        layer.add(fade, forKey: "fade")
    }
}

/// Sets `field` to `text` on one line, centred, at most `maxWidth` wide: a line that doesn't fit
/// is set up to a fifth smaller, then cut short with an ellipsis. Sized from the text itself:
/// a label's `fittingSize` follows Auto Layout's preferred width, and wrapped at first.
@MainActor
private func fit(_ field: NSTextField, _ text: NSAttributedString, maxWidth: CGFloat) {
    // What a label cell adds around its text.
    let padding: CGFloat = 4
    let line = NSMutableAttributedString(attributedString: text)
    let natural = line.size().width
    if natural + padding > maxWidth, natural > 0 {
        // A hair under, so rounding doesn't tip it into an ellipsis.
        let scale = max(0.8, (maxWidth - padding) / natural * 0.99)
        line.enumerateAttribute(.font, in: NSRange(location: 0, length: line.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            line.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: font.pointSize * scale), range: range)
        }
    }
    let size = line.size()
    let truncates = size.width + padding > maxWidth
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = truncates ? .byTruncatingTail : .byClipping
    line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))

    field.usesSingleLineMode = true
    field.maximumNumberOfLines = 1
    field.cell?.wraps = false
    field.lineBreakMode = style.lineBreakMode
    field.attributedStringValue = line
    field.setFrameSize(NSSize(width: min(ceil(size.width + padding), maxWidth), height: ceil(size.height)))
}

/// One entry's text: the format (or JPEG quality) over its estimate, centred on a point. The
/// highlighted entry's format turns the accent colour and grows a little.
@MainActor
private final class EntryLabel: NSView {
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private var isHighlighted = false
    private var shownSubtitle: String?

    /// Where its middle goes, in its superview.
    var centre: CGPoint = .zero

    /// The accent, a little deeper on light glass and lighter on dark glass, so it reads on the
    /// highlight's tint of the same colour.
    private static let accent = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor.controlAccentColor.blended(withFraction: dark ? 0.45 : 0.3, of: dark ? .white : .black)
            ?? .controlAccentColor
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        for field in [title, subtitle] {
            field.alignment = .center
            addSubview(field)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ entry: RingLook.Entry, highlighted: Bool, maxWidth: CGFloat, reduceMotion: Bool) {
        let accented = highlighted || entry.isAdded
        let line = NSMutableAttributedString(string: entry.title, attributes: [
            .font: NSFont.systemFont(ofSize: 14.5, weight: .semibold),
            .foregroundColor: accented ? Self.accent : NSColor.labelColor,
        ])
        if entry.isAdded {
            line.append(NSAttributedString(string: " ✓", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: Self.accent,
            ]))
        } else if entry.isDefault {
            // The stored default among the fanned-out qualities: a small dot after its name.
            line.append(NSAttributedString(string: " ●", attributes: [
                .font: NSFont.systemFont(ofSize: 6), .foregroundColor: Self.accent, .baselineOffset: 3,
            ]))
        }
        fit(title, line, maxWidth: maxWidth)

        if let shown = shownSubtitle, shown != entry.subtitle, let layer = subtitle.layer ?? layer {
            // A refined estimate ("~19 MB" to "19 MB") changes in place, with a quick dissolve.
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.2
            layer.add(fade, forKey: "text")
        }
        shownSubtitle = entry.subtitle
        fit(subtitle, NSAttributedString(string: entry.subtitle, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]), maxWidth: maxWidth)

        let width = max(title.frame.width, subtitle.frame.width)
        let height = title.frame.height + subtitle.frame.height
        frame = NSRect(x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height)
        title.setFrameOrigin(NSPoint(x: (width - title.frame.width) / 2, y: subtitle.frame.height))
        subtitle.setFrameOrigin(NSPoint(x: (width - subtitle.frame.width) / 2, y: 0))

        if highlighted != isHighlighted {
            isHighlighted = highlighted
            grow(to: highlighted ? 1.06 : 1, animated: !reduceMotion)
        } else if let layer {
            layer.sublayerTransform = scale(highlighted ? 1.06 : 1)
        }
    }

    /// Pops in: from small and clear to its size, after `delay`. With Reduce Motion, it fades.
    func pop(after delay: TimeInterval, reduceMotion: Bool) {
        guard let layer else { return }
        let start = CACurrentMediaTime() + delay
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.2
        fade.beginTime = start
        fade.fillMode = .backwards
        layer.add(fade, forKey: "pop fade")
        guard !reduceMotion else { return }
        let spring = CASpringAnimation(perceptualDuration: 0.32, bounce: 0.3)
        spring.keyPath = "sublayerTransform"
        spring.fromValue = scale(0.6)
        spring.toValue = layer.sublayerTransform
        spring.duration = spring.settlingDuration
        spring.beginTime = start
        spring.fillMode = .backwards
        layer.add(spring, forKey: "pop")
    }

    private func grow(to factor: CGFloat, animated: Bool) {
        guard let layer else { return }
        let from = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        layer.sublayerTransform = scale(factor)
        guard animated else { return }
        let spring = CASpringAnimation(perceptualDuration: 0.25, bounce: 0.3)
        spring.keyPath = "sublayerTransform"
        spring.fromValue = from
        spring.toValue = scale(factor)
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "grow")
    }

    /// `factor` about its middle, for `sublayerTransform`.
    private func scale(_ factor: CGFloat) -> CATransform3D {
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        var transform = CATransform3DMakeTranslation(middle.x, middle.y, 0)
        transform = CATransform3DScale(transform, factor, factor, 1)
        return CATransform3DTranslate(transform, -middle.x, -middle.y, 0)
    }
}

/// The ring's own window: the size of the ring, above the panels that catch the drag, and
/// ignoring the mouse so the drag goes through to them. It fades out after the ring closes,
/// which the catching panels can't do: they must stop catching at once.
@MainActor
final class RingWindow {
    let ringView = RingView()
    private let panel: NSPanel
    /// Counts shows, so a fade-out that finishes after the next show leaves it alone.
    private var shows = 0

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: RingView.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Unlike the catching panels: the drag must go through this one to them.
        panel.ignoresMouseEvents = true
        panel.contentView = ringView
        #if DEBUG
        // `-RingAppearance dark` (or light): the ring in that appearance, whatever the Mac's.
        if let name = UserDefaults.standard.string(forKey: "RingAppearance") {
            panel.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
        }
        #endif
    }

    /// Shows the ring centred on `centre` (screen coordinates).
    func show(at centre: NSPoint) {
        shows += 1
        let size = RingView.size
        panel.setFrame(NSRect(x: (centre.x - size.width / 2).rounded(), y: (centre.y - size.height / 2).rounded(),
                              width: size.width, height: size.height), display: false)
        ringView.reset()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        ringView.appear()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        let show = shows
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.shows == show else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}
