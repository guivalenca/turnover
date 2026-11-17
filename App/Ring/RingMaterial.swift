import AppKit

/// The ring's material: the system's Liquid Glass (regular, not clear) on macOS 26 and later, the
/// system vibrancy material on macOS 15. Both follow Reduce Transparency and Increase Contrast by
/// themselves.
@MainActor
enum RingMaterial {
    /// Liquid Glass is available and not turned off for testing. In Debug builds, the launch
    /// argument `-RingMaterial vibrancy` shows macOS 15's look on a newer Mac.
    static var usesGlass: Bool {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "RingMaterial") == "vibrancy" { return false }
        #endif
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// A shape of glass with rounded corners (a circle when `cornerRadius` is half its size) that
    /// holds `content`. `lens` is a shape that sits over another one (the hub over the band).
    static func surface(frame: NSRect, cornerRadius: CGFloat, content: NSView, lens: Bool = false) -> NSView {
        if usesGlass, #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            content.frame = glass.bounds
            content.autoresizingMask = [.width, .height]
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView(frame: frame)
        effect.material = .menu
        // The hub blends with the band under it, so it reads as a lens; the rest with the screen.
        effect.blendingMode = lens ? .withinWindow : .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(cornerRadius)
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }

    /// A stretchable mask with round corners, as `NSVisualEffectView.maskImage` documents.
    private static func roundedMask(_ radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Reduce Motion, read when the ring opens. In Debug builds, `-RingReduceMotion YES` turns it on
/// without changing the Mac's setting.
@MainActor
enum RingMotion {
    static var isReduced: Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "RingReduceMotion") != nil {
            return UserDefaults.standard.bool(forKey: "RingReduceMotion")
        }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
