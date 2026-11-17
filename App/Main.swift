import AppKit

/// Turnover.app: a background agent (LSUIElement, so no Dock icon) that owns every conversion.
@main
@MainActor
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
