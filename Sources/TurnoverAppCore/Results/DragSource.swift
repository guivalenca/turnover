import Foundation

/// Where a drag of files started: the Desktop, a Finder window or somewhere else, read from
/// the windows on screen when the button went down. Each window comes from
/// `CGWindowListCopyWindowInfo`, which gives owners, levels and bounds without any permission
/// (only window names need Screen Recording, and they aren't read).
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
        /// `.desktopIconWindow`: Finder's window of Desktop icons.
        public var desktopIcons: Int
        /// `.normalWindow`: Finder's browser windows.
        public var normal: Int
        /// `.draggingWindow`: the drag image, which may already be under the pointer.
        public var dragging: Int

        public init(desktopIcons: Int, normal: Int, dragging: Int) {
            self.desktopIcons = desktopIcons
            self.normal = normal
            self.dragging = dragging
        }
    }

    /// The source of a drag that started at `point`, given the windows on screen from front
    /// to back, without Turnover's own. The frontmost window under the point decides; the drag
    /// image and anything above it is skipped.
    public init(at point: CGPoint, windows: [Window], levels: Levels) {
        guard let window = windows.first(where: { $0.layer < levels.dragging && $0.frame.contains(point) }),
              window.isFinder
        else { self = .elsewhere; return }
        switch window.layer {
        case levels.desktopIcons: self = .desktop
        case levels.normal: self = .finderWindow
        default: self = .elsewhere
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
