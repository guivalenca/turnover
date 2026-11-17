import Foundation

extension Bundle {
    /// Where a target of this package keeps its user-facing strings: the resource bundle SwiftPM
    /// and Xcode build from its `Localizable.xcstrings`, `Turnover_<target>.bundle`. That sits in
    /// the app's or the extension's Resources, or next to the `turnover` command or the tests.
    ///
    /// Not `Bundle.module`: SwiftPM's accessor stops the process when the bundle isn't where it
    /// was built, and the `turnover` command may be copied anywhere. Without its bundle, a string
    /// is its English source text: right, but for plurals of one ("1 files").
    package static func strings(of target: String) -> Bundle {
        let name = "Turnover_\(target).bundle"
        let code = Bundle(for: StringsMarker.self)
        let places = [Bundle.main.resourceURL, Bundle.main.bundleURL, code.resourceURL,
                      code.bundleURL.deletingLastPathComponent()]
        for case let place? in places {
            if let bundle = Bundle(url: place.appendingPathComponent(name)) { return bundle }
        }
        return .main
    }

    /// TurnoverKit's strings.
    static let turnoverKit = strings(of: "TurnoverKit")
}

private final class StringsMarker {}
