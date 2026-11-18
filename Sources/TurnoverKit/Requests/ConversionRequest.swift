import Foundation

/// A request to convert files to one format, as the Finder extension hands it to the app:
/// `turnover://convert?to=png&file=/path/a.heic&file=/path/b.heic`.
///
/// The sandboxed extension can't convert or write files, so it opens this URL and the app,
/// which registers the `turnover` scheme, does the work.
public struct ConversionRequest: Sendable, Hashable {
    /// The URL scheme the app registers.
    public static let scheme = "turnover"

    public let format: OutputFormat
    /// The files to convert, as absolute file URLs, in the order given.
    public let files: [URL]

    public init(format: OutputFormat, files: [URL]) {
        self.format = format
        self.files = files
    }

    /// Reads the request in `url`, which any process may have opened. Only what the extension
    /// sends is taken: `convert`, one known format, and one or more absolute paths to files that
    /// exist. Anything else throws, and nothing in it is acted on.
    ///
    /// Even a forged request can only make new files next to existing ones: converting never
    /// changes or replaces a file.
    public init(_ url: URL) throws(Invalid) {
        func refuse(_ reason: String) -> Invalid { Invalid(url: url, reason: reason) }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme
        else { throw refuse("not a \(Self.scheme): URL") }
        guard components.host == "convert", components.path.isEmpty
        else { throw refuse("unknown action") }

        let items = components.queryItems ?? []
        if let unknown = items.first(where: { !["to", "file"].contains($0.name) }) {
            throw refuse("unknown parameter \(unknown.name)")
        }
        let formats = items.filter { $0.name == "to" }.map { $0.value.flatMap(OutputFormat.init(conversion:)) }
        guard formats.count == 1, let format = formats[0] else { throw refuse("needs exactly one known format") }

        let paths = items.filter { $0.name == "file" }.map { $0.value ?? "" }
        guard !paths.isEmpty else { throw refuse("no files") }
        var files: [URL] = []
        var seen: Set<String> = []
        for path in paths where seen.insert(path).inserted {  // a forged URL can't multiply copies
            guard path.hasPrefix("/") else { throw refuse("not an absolute path: \(path)") }
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), !isFolder.boolValue
            else { throw refuse("no such file: \(path)") }
            files.append(URL(fileURLWithPath: path))
        }
        self.format = format
        self.files = files
    }

    /// Why a URL was refused.
    public struct Invalid: Error, Sendable, Hashable, CustomStringConvertible {
        public let url: URL
        public let reason: String
        public var description: String { "refused \(url.absoluteString): \(reason)" }
    }

    /// The URL to open to send the request.
    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "convert"
        components.queryItems = [URLQueryItem(name: "to", value: format.rawValue)]
            + files.map { URLQueryItem(name: "file", value: $0.path) }
        return components.url!
    }
}
