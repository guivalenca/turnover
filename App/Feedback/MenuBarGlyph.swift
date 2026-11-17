import AppKit

/// The menu bar item's glyph: a template version of the app icon.
enum MenuBarGlyph {
    /// The asset catalog's "MenuBarGlyph" template image (#14). Until it lands, a system symbol
    /// stands in.
    static var image: NSImage {
        let image = NSImage(named: "MenuBarGlyph")
            ?? NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Turnover")!
        image.isTemplate = true
        image.accessibilityDescription = "Turnover"
        return image
    }
}
