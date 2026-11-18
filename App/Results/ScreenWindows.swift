import AppKit
import TurnoverAppCore

extension DragSource {
    /// Where a drag that started at `point` (AppKit screen coordinates) came from, read from
    /// the windows on screen now. Needs no permission: window names aren't read.
    @MainActor static func current(at point: NSPoint) -> DragSource {
        let finder = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .map(\.processIdentifier))
        let me = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] ?? []
        let windows: [Window] = list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID] as? pid_t, pid != me,
                  let layer = info[kCGWindowLayer] as? Int,
                  let bounds = info[kCGWindowBounds] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  (info[kCGWindowAlpha] as? Double ?? 1) > 0
            else { return nil }
            return Window(isFinder: finder.contains(pid), layer: layer, frame: frame)
        }
        let levels = Levels(
            desktopIcons: Int(CGWindowLevelForKey(.desktopIconWindow)),
            normal: Int(CGWindowLevelForKey(.normalWindow)),
            dragging: Int(CGWindowLevelForKey(.draggingWindow)))
        return DragSource(at: DesktopCoordinates.current.topLeft(point), windows: windows, levels: levels)
    }
}
