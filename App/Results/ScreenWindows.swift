import AppKit
import TurnoverAppCore

/// The windows on screen now, from front to back, without Turnover's own: who owns each, its
/// level and its frame. Needs no permission: window names aren't read.
@MainActor
struct ScreenWindows {
    let windows: [DragSource.Window]
    let levels: DragSource.Levels
    /// The screens' frames, in the same global, top-left-origin points as the windows'.
    let screens: [CGRect]
    /// Each window's owner's name, for the log.
    private let owners: [String]

    init() {
        let finder = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .map(\.processIdentifier))
        let me = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] ?? []
        var owners: [String] = []
        windows = list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID] as? pid_t, pid != me,
                  let layer = info[kCGWindowLayer] as? Int,
                  let bounds = info[kCGWindowBounds] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  (info[kCGWindowAlpha] as? Double ?? 1) > 0
            else { return nil }
            owners.append(info[kCGWindowOwnerName] as? String ?? "?")
            return DragSource.Window(isFinder: finder.contains(pid), layer: layer, frame: frame, owner: pid)
        }
        self.owners = owners
        levels = DragSource.Levels(
            normal: Int(CGWindowLevelForKey(.normalWindow)),
            dragging: Int(CGWindowLevelForKey(.draggingWindow)))
        screens = NSScreen.screens.map { DesktopCoordinates.current.topLeft($0.frame) }
    }

    /// The frontmost window under `point` (global, top-left-origin points), seeing through the
    /// drag image and overlays.
    func frontmost(at point: CGPoint) -> DragSource.Window? {
        DragSource.Window.frontmost(at: point, among: windows, levels: levels, screens: screens)
    }

    /// The windows under `point`, front to back, for the log: "Safari@0 1200×800".
    func described(under point: CGPoint) -> String {
        zip(windows, owners).filter { $0.0.frame.contains(point) }
            .map { "\($1)@\($0.layer) \(Int($0.frame.width))×\(Int($0.frame.height))" }
            .joined(separator: ", ")
    }
}

extension DragSource {
    /// Where a drag of `files` that started at `point` (AppKit screen coordinates) came from,
    /// read from the windows on screen now.
    @MainActor static func current(of files: [URL], at point: NSPoint) -> DragSource {
        let screen = ScreenWindows()
        let topLeft = DesktopCoordinates.current.topLeft(point)
        let source = DragSource(of: files, at: topLeft, windows: screen.windows, levels: screen.levels,
                                screens: screen.screens, desktopFolder: FinderDesktop.folder)
        ringLog.debug("Windows under the drag's start, front to back: \(screen.described(under: topLeft), privacy: .public)")
        return source
    }
}

extension SaveDestination {
    /// Where an image dragged from a window of `source`, and dropped on the ring at `point`
    /// (AppKit screen coordinates), is saved: read from the windows on screen now.
    @MainActor static func current(droppedAt point: NSPoint, draggedFrom source: pid_t?) -> SaveDestination {
        let screen = ScreenWindows()
        let topLeft = DesktopCoordinates.current.topLeft(point)
        ringLog.debug("Windows under the drop, front to back: \(screen.described(under: topLeft), privacy: .public)")
        return SaveDestination(droppedAt: topLeft, draggedFrom: source, windows: screen.windows, levels: screen.levels,
                               screens: screen.screens)
    }
}
