import AppKit
import RingModel

/// Debug builds only: shows the glass ring in a given state, with no drag, so its look can be
/// checked and captured. It takes no input; quit the app to close it. While it runs, the app
/// opens no window of its own.
///
///     Turnover.app/Contents/MacOS/Turnover -RingPreview photos -RingHighlight 1
///
/// States: `movie`, `photos`, `fanned` (⌥ over images), `mixed` (images and a video),
/// `mixed-added` (PNG added), `mixed-fanned`, `long` (the longest texts), and `none` (no
/// preview: for trying the real ring with drags, without the window).
/// Also: `-RingHighlight <index>` (none: the hub's resting text), `-RingTour YES` (moves the
/// highlight round every second), `-RingAt x,y` (opens there, kept on screen as a real ring is),
/// `-RingMaterial vibrancy` (macOS 15's material), `-RingReduceMotion YES`, and
/// `-RingAppearance dark` (the Mac's own appearance can't be overridden per app from the command
/// line).
@MainActor
enum RingPreview {
    /// A preview was asked for (Debug builds only).
    static var isRunning: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "RingPreview") != nil
        #else
        false
        #endif
    }

    #if DEBUG
    private static var window: RingWindow?
    private static var tour: Timer?

    static func showIfAsked() {
        let defaults = UserDefaults.standard
        guard let name = defaults.string(forKey: "RingPreview"), name != "none" else { return }
        guard var look = look(named: name) else {
            ringLog.error("No ring preview named \(name, privacy: .public)")
            return
        }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        var point = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        if let at = defaults.string(forKey: "RingAt")?.split(separator: ",").compactMap({ Double($0) }), at.count == 2 {
            point = NSPoint(x: at[0], y: at[1])
        }
        let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let centre = RingGeometry.centre(openingAt: point, drawing: RingView.drawing, within: area)
        let window = RingWindow()
        self.window = window
        window.show(at: centre)

        if defaults.object(forKey: "RingHighlight") != nil {
            look = highlighting(defaults.integer(forKey: "RingHighlight"), in: look)
        }
        window.ringView.look = look
        ringLog.notice("Ring preview \(name, privacy: .public) at \(NSStringFromPoint(centre), privacy: .public)")

        guard defaults.bool(forKey: "RingTour") else { return }
        var step = 0
        tour = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                step += 1
                let index = step % (look.entries.count + 1)
                let next = highlighting(index == look.entries.count ? nil : index, in: look)
                window.ringView.pointerAngle = index < next.entries.count ? next.entries[index].angle : nil
                window.ringView.look = next
            }
        }
    }

    /// `look` with the entry at `index` highlighted, and the hub saying what a drop there does.
    private static func highlighting(_ index: Int?, in look: RingLook) -> RingLook {
        var look = look
        guard let index, look.entries.indices.contains(index) else {
            look.highlighted = nil
            look.restingFor = nil
            return look
        }
        look.highlighted = index
        let entry = look.entries[index]
        let added = look.entries.filter(\.isAdded).map(\.title)
        if !added.isEmpty, !entry.isAdded {
            look.hub = .init(title: (added + [entry.title]).joined(separator: " + "), detail: "4 files")
        } else if ["Best", "High", "Small"].contains(entry.title) {
            look.hub = .init(title: "JPEG", detail: "\(entry.title) · \(entry.subtitle)")
        } else {
            look.hub = .init(title: entry.title, detail: entry.subtitle)
        }
        if look.caption != nil, !entry.isAdded { look.restingFor = 0.5 }
        return look
    }

    private static func look(named name: String) -> RingLook? {
        switch name {
        case "movie":
            return RingLook(entries: placed([("MP4", "About 5 s", -90)]), hub: .init(title: "1", detail: "video"))
        case "photos":
            return RingLook(entries: placed([("PNG", "~19 MB", 180), ("JPEG", "2.4 MB", 0)]),
                            hub: .init(title: "3", detail: "images"))
        case "fanned":
            var entries = placed([("PNG", "~19 MB", 180), ("Best", "~6.1 MB", -54), ("High", "2.4 MB", 0),
                                  ("Small", "~1.1 MB", 54)])
            entries[2].isDefault = true
            return RingLook(entries: entries, hub: .init(title: "JPEG", detail: "quality"))
        case "mixed":
            return RingLook(entries: placed([("PNG", "~19 MB", 143), ("JPEG", "2.4 MB", -143), ("MP4", "About 12 s", 0)]),
                            hub: .init(title: "4", detail: "files"),
                            caption: "Rest on a format to add it, then drop on another")
        case "mixed-added":
            var entries = placed([("PNG", "~19 MB", 143), ("JPEG", "2.4 MB", -143), ("MP4", "About 12 s", 0)])
            entries[0].isAdded = true
            return RingLook(entries: entries, hub: .init(title: "4", detail: "files"),
                            caption: "PNG added · drop to convert")
        case "mixed-fanned":
            var entries = placed([("PNG", "~19 MB", 102), ("Best", "~6.1 MB", 154), ("High", "2.4 MB", -154),
                                  ("Small", "~1.1 MB", -102), ("MP4", "About 12 s", 0)])
            entries[2].isDefault = true
            return RingLook(entries: entries, hub: .init(title: "JPEG", detail: "quality"),
                            caption: "Rest on a format to add it, then drop on another")
        case "long":
            var entries = placed([("PNG", "~888 MB", 102), ("Best", "~1.2 GB", 154), ("Small", "~123 MB", -154),
                                  ("High", "~999 MB", -102), ("MP4", "About 59 min", 0)])
            entries[3].isAdded = true
            return RingLook(entries: entries, hub: .init(title: "JPEG + MP4", detail: "Best · ~1.2 GB"),
                            caption: "JPEG 100% + MP4 added · drop to convert, and this caption is far too long to fit")
        default:
            return nil
        }
    }

    /// Entries at the given angles, each owning the arc halfway to its neighbours.
    private static func placed(_ items: [(String, String, Double)]) -> [RingLook.Entry] {
        let angles = items.map(\.2)
        return items.map { title, subtitle, angle in
            let others = angles.filter { $0 != angle }
            guard !others.isEmpty else {
                return RingLook.Entry(title: title, subtitle: subtitle, angle: angle, arcStart: angle - 180, arcEnd: angle + 180)
            }
            let clockwise = others.map { other -> Double in
                let d = (other - angle).truncatingRemainder(dividingBy: 360)
                return d <= 0 ? d + 360 : d
            }
            return RingLook.Entry(title: title, subtitle: subtitle, angle: angle,
                                  arcStart: angle - (360 - clockwise.max()!) / 2, arcEnd: angle + clockwise.min()! / 2)
        }
    }
    #endif
}
