import Foundation

/// Where a drag of files started: the Desktop, a Finder window or somewhere else.
///
/// A Finder window is told by the windows on screen when the button went down, from
/// `CGWindowListCopyWindowInfo`, which gives owners, levels and bounds without any permission
/// (only window names need Screen Recording, and they aren't read). The Desktop can't be told
/// that way: on recent macOS, Finder's window of Desktop icons isn't in that list, and windows
/// moved aside to show the Desktop keep their old bounds there. So a drag that didn't start
/// in a Finder window is the Desktop's when every dragged file is directly on the Desktop.
public enum DragSource: Sendable, Equatable {
    case desktop
    case finderWindow
    case elsewhere

    /// A window on screen, as `CGWindowListCopyWindowInfo` lists it.
    public struct Window: Sendable, Equatable {
        /// Whether Finder owns it.
        public var isFinder: Bool
        /// Its window level (`kCGWindowLayer`).
        public var layer: Int
        /// Its frame in global, top-left-origin points.
        public var frame: CGRect

        public init(isFinder: Bool, layer: Int, frame: CGRect) {
            self.isFinder = isFinder
            self.layer = layer
            self.frame = frame
        }
    }

    /// Window levels, from `CGWindowLevelForKey`.
    public struct Levels: Sendable, Equatable {
        /// `.normalWindow`: Finder's browser windows.
        public var normal: Int
        /// `.draggingWindow`: the drag image, which may already be under the pointer.
        public var dragging: Int

        public init(normal: Int, dragging: Int) {
            self.normal = normal
            self.dragging = dragging
        }
    }

    /// The source of a drag of `files` that started at `point`, given the windows on screen
    /// from front to back, without Turnover's own, and the screens' frames. The frontmost
    /// window under the point says whether it is a Finder window. The drag image and anything
    /// above it are seen through, and so are overlays: windows above the normal level that
    /// cover a whole screen, like the one the Dock puts up while something is dragged.
    public init(of files: [URL], at point: CGPoint, windows: [Window], levels: Levels, screens: [CGRect], desktopFolder: URL) {
        let window = windows.first { window in
            let isOverlay = window.layer > levels.normal && screens.contains { window.frame.contains($0) }
            return window.layer < levels.dragging && !isOverlay && window.frame.contains(point)
        }
        if let window, window.isFinder, window.layer == levels.normal {
            self = .finderWindow
        } else if ConversionOrigin(menuFiles: files, desktopFolder: desktopFolder) == .desktop(drop: nil) {
            self = .desktop
        } else {
            self = .elsewhere
        }
    }

    /// The conversion's origin, for a ring dropped at `drop`.
    public func origin(drop: CGPoint) -> ConversionOrigin {
        switch self {
        case .desktop: .desktop(drop: drop)
        case .finderWindow: .finderWindow
        case .elsewhere: .elsewhere
        }
    }
}
