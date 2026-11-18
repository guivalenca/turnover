import Foundation

/// Where an image dragged out of a web page is saved. It has no folder of its own, so what the
/// ring was dropped over says: the Desktop, a Finder window, or anything else, which means
/// Downloads.
///
/// Points are in Finder's desktop coordinates, like `ConversionOrigin`'s.
public enum SaveDestination: Sendable, Equatable {
    /// Over the bare Desktop: on the Desktop, where it was dropped.
    case desktop(drop: CGPoint)
    /// Over a Finder window: in the folder that window shows. Only Finder knows which folder, so
    /// it is asked: `frame` is the window's, and `drop` a point in it.
    case finderWindow(drop: CGPoint, frame: CGRect)
    /// Anywhere else: in Downloads. `copied` when it was dropped over a window of another app
    /// than the one it was dragged from: the new file is also put on the clipboard, ready to
    /// paste there, since the drop itself can't reach that app.
    case downloads(copied: Bool)

    /// The destination for a ring dropped at `point`, given the windows on screen from front to
    /// back, without Turnover's own, and the screens' frames. `source` is the process whose
    /// window the image was dragged from, if known.
    ///
    /// The frontmost window under the point decides (`DragSource.Window.frontmost`). Below the
    /// normal level there is only the Desktop: the wallpaper, and Finder's icons where they are
    /// listed. A Finder window at the normal level is a folder. Any other window is Downloads,
    /// and only a normal window of another app is somewhere to paste: not the Dock or the menu
    /// bar, and not the browser the image came from.
    ///
    /// Windows moved aside to show the Desktop keep their old frames in the list, so a drop on
    /// the Desktop where one of them was counts as a drop on that window.
    public init(droppedAt point: CGPoint, draggedFrom source: Int32?, windows: [DragSource.Window],
                levels: DragSource.Levels, screens: [CGRect]) {
        let window = DragSource.Window.frontmost(at: point, among: windows, levels: levels, screens: screens)
        guard let window, window.layer >= levels.normal else {
            self = .desktop(drop: point)
            return
        }
        if window.isFinder, window.layer == levels.normal {
            self = .finderWindow(drop: point, frame: window.frame)
        } else {
            self = .downloads(copied: window.layer == levels.normal && window.owner != source)
        }
    }
}
