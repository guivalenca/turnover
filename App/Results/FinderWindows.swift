import AppKit
import os

private let windowsLog = Logger(subsystem: "com.guivalenca.turnover", category: "finder-windows")

/// Which folder a Finder window shows. Only Finder knows, so it is asked over Apple Events, the
/// way the Desktop's icons are (`FinderDesktop`), under the same permission.
enum FinderWindows {
    /// One request at a time, off the main actor: the first one waits for the permission prompt.
    private static let queue = DispatchQueue(label: "com.guivalenca.turnover.finder-windows", qos: .userInitiated)

    /// The folder shown by the Finder window whose frame is `frame` and that `point` is in (both
    /// in Finder's desktop coordinates). Nil when Finder refused, or when the window shows
    /// something that isn't a folder to save in: Recents, a search, AirDrop, the Trash.
    static func folder(at point: CGPoint, inWindow frame: CGRect) async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async {
                let arguments = [point.x, point.y, frame.minX, frame.minY, frame.maxX, frame.maxY]
                    .map { String(Int($0.rounded())) }
                let said = FinderScript.run(script, arguments: arguments, what: "say which folder a window shows", log: windowsLog)
                var isFolder: ObjCBool = false
                guard let path = said, path.hasPrefix("/"),
                      FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue
                else {
                    windowsLog.notice("No folder for the Finder window under the drop: Finder said “\(said ?? "nothing", privacy: .public)”")
                    return continuation.resume(returning: nil)
                }
                continuation.resume(returning: URL(fileURLWithPath: path, isDirectory: true))
            }
        }
    }

    /// `argv` is the point's x and y, then the window's left, top, right and bottom. Prints the
    /// POSIX path of the folder shown by the frontmost Finder window that lies within that frame
    /// and has the point in it, or nothing.
    ///
    /// Finder lists its windows from front to back, and gives each one's bounds without its
    /// title bar, so the frame says which window and the point tells it from a smaller one in
    /// front of it. A few points of slack cover rounding.
    private static let script = [
        "on run argv",
        "  set px to (item 1 of argv) as integer",
        "  set py to (item 2 of argv) as integer",
        "  set fl to ((item 3 of argv) as integer) - 4",
        "  set ft to ((item 4 of argv) as integer) - 4",
        "  set fr to ((item 5 of argv) as integer) + 4",
        "  set fb to ((item 6 of argv) as integer) + 4",
        "  tell application \"Finder\"",
        "    repeat with w in (get every Finder window)",
        "      set b to bounds of w",
        "      set inFrame to (item 1 of b) >= fl and (item 2 of b) >= ft and (item 3 of b) <= fr and (item 4 of b) <= fb",
        "      if inFrame and px >= (item 1 of b) - 4 and px <= (item 3 of b) + 4 and py >= ft and py <= (item 4 of b) + 4 then",
        "        try",
        "          return POSIX path of ((target of w) as alias)",
        "        on error",
        "          return \"\"",
        "        end try",
        "      end if",
        "    end repeat",
        "  end tell",
        "  return \"\"",
        "end run",
    ]
}
