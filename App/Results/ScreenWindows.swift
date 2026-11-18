import AppKit
import TurnoverAppCore

extension DragSource {
    /// Where a drag of `files` that started at `point` (AppKit screen coordinates) came from,
    /// read from the windows on screen now. Needs no permission: window names aren't read.
    @MainActor static func current(of files: [URL], at point: NSPoint) -> DragSource {
        let finder = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .map(\.processIdentifier))
        let me = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] ?? []
        let topLeft = DesktopCoordinates.current.topLeft(point)
        var under: [String] = []
        let windows: [Window] = list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID] as? pid_t, pid != me,
                  let layer = info[kCGWindowLayer] as? Int,
                  let bounds = info[kCGWindowBounds] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  (info[kCGWindowAlpha] as? Double ?? 1) > 0
            else { return nil }
            if frame.contains(topLeft) { under.append("\(info[kCGWindowOwnerName] as? String ?? "?")@\(layer)") }
            return Window(isFinder: finder.contains(pid), layer: layer, frame: frame)
        }
        let levels = Levels(
            normal: Int(CGWindowLevelForKey(.normalWindow)),
            dragging: Int(CGWindowLevelForKey(.draggingWindow)))
        let source = DragSource(of: files, at: topLeft, windows: windows, levels: levels, desktopFolder: FinderDesktop.folder)
        ringLog.debug("Windows under the drag's start, front to back: \(under.joined(separator: ", "), privacy: .public)")
        return source
    }
}
