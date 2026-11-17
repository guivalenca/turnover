import TurnoverKit

/// A parsed command line: `turnover <files…> --to <format>`.
struct Command {
    /// The formats `--to` accepts, each with the action it runs.
    static let formats: KeyValuePairs<String, any ConversionAction> = [
        "png": PNGAction(),
        "jpeg": JPEGAction(),
    ]

    static let usage = """
        usage: turnover <files…> --to <format>

        Converts each file and saves the result next to it, with the same name and the new
        extension (numbered if that name is taken). Prints the path of each new file.
        Originals are never modified.

        formats: \(formats.map(\.key).joined(separator: ", "))
        """

    enum Parsed {
        case convert(files: [String], action: any ConversionAction)
        case help
    }

    struct UsageError: Error {
        let message: String
    }

    static func parse(_ arguments: [String]) throws(UsageError) -> Parsed {
        var files: [String] = []
        var format: String?
        var quality: String?
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "-h", "--help":
                return .help
            case "--to":
                guard let value = remaining.popFirst() else { throw UsageError(message: "--to needs a format") }
                format = value
            case _ where argument.hasPrefix("--to="):
                format = String(argument.dropFirst("--to=".count))
            case "--quality":
                guard let value = remaining.popFirst() else { throw UsageError(message: "--quality needs a value") }
                quality = value
            case _ where argument.hasPrefix("--quality="):
                quality = String(argument.dropFirst("--quality=".count))
            case "--":
                files.append(contentsOf: remaining)
                remaining = []
            case _ where argument.hasPrefix("-") && argument != "-":
                throw UsageError(message: "unknown option \(argument)")
            default:
                files.append(argument)
            }
        }
        guard let format else { throw UsageError(message: "missing --to <format>") }
        guard var action = formats.first(where: { $0.key == format.lowercased() })?.value
        else { throw UsageError(message: "unknown format '\(format)'") }
        if let quality {
            guard let preset = JPEGQuality(rawValue: quality.lowercased())
            else { throw UsageError(message: "unknown quality '\(quality)'") }
            action = JPEGAction(quality: preset)
        }
        guard !files.isEmpty else { throw UsageError(message: "no files given") }
        return .convert(files: files, action: action)
    }
}
