import Foundation

/// Where a conversion was started, which decides what happens to its new files (#18).
///
/// Points are in Finder's desktop coordinates: the origin is the top-left corner of the main
/// screen, and y grows downwards. `DesktopCoordinates` converts AppKit's screen points.
public enum ConversionOrigin: Sendable, Equatable {
    /// A Finder window: the new files are selected there, ready to drag on.
    case finderWindow
    /// The Desktop. `drop` is where the ring was dropped, or nil when the right-click menu
    /// started the conversion.
    case desktop(drop: CGPoint?)
    /// Anywhere else, such as a Dock stack or another app. No Finder window opens.
    case elsewhere

    /// The origin of a conversion from the Finder menu, which only lists the files. A menu on
    /// files that are all on the Desktop is taken to be the Desktop's own; a Finder window
    /// showing the Desktop folder is rare, and in it the new file still shows up, unselected.
    public init(menuFiles files: [URL], desktopFolder: URL) {
        let desktop = desktopFolder.standardizedFileURL.path
        let onDesktop = !files.isEmpty && files.allSatisfy {
            $0.standardizedFileURL.deletingLastPathComponent().path == desktop
        }
        self = onDesktop ? .desktop(drop: nil) : .finderWindow
    }

    /// What happens to the batch's new files.
    public var handling: ResultHandling {
        switch self {
        case .finderWindow: .selectInFinder
        case .desktop(let drop?): .placeOnDesktop(at: drop)
        case .desktop(nil), .elsewhere: .leave
        }
    }
}

/// What happens to a batch's new files once they exist.
public enum ResultHandling: Sendable, Equatable {
    /// Select them in Finder when the batch ends. Finder reuses a window that shows their
    /// folder, if there is one.
    case selectInFinder
    /// Put each one that lands on the Desktop at the next slot from this point, as it lands.
    case placeOnDesktop(at: CGPoint)
    /// Leave them where Finder puts them, and open nothing.
    case leave

    /// The files `placeOnDesktop` moves: the ones saved in the Desktop folder itself. A file
    /// that went to Downloads instead, because the Desktop was read-only, stays put.
    public static func placeable(_ outputs: [URL], desktopFolder: URL) -> [URL] {
        let desktop = desktopFolder.standardizedFileURL.path
        return outputs.filter { $0.standardizedFileURL.deletingLastPathComponent().path == desktop }
    }
}

/// Converts between AppKit's screen points (origin at the main screen's bottom-left, y up) and
/// the global, top-left-origin points that Finder and `CGWindowListCopyWindowInfo` use.
public struct DesktopCoordinates: Sendable, Equatable {
    /// The height of the main screen, the one with the menu bar (`NSScreen.screens[0]`).
    public var mainScreenHeight: CGFloat

    public init(mainScreenHeight: CGFloat) {
        self.mainScreenHeight = mainScreenHeight
    }

    public func topLeft(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: mainScreenHeight - point.y)
    }

    public func topLeft(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
