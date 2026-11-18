import AppKit

extension NSPanel {
    /// A borderless, clear panel above other apps' windows, on every Space and over full-screen
    /// apps, that never activates Turnover: what the ring, the panels catching its drag and the
    /// hint are shown in.
    ///
    /// `ignoresMouse` is always set explicitly. Left unset, the window server lets drags and
    /// clicks through wherever the panel is fully transparent: the ring's catching panels lost
    /// the drag as soon as it left the drawn disc, and Finder under them took the drop.
    static func overlay(size: NSSize = .zero, ignoresMouse: Bool, shadow: Bool = false) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = shadow
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = ignoresMouse
        return panel
    }
}
