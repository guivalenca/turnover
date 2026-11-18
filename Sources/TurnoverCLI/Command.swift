import TurnoverKit

/// A parsed command line: `turnover <files…> --to <format> [--quality <quality>]`. `--to` takes
/// any format files convert to (`OutputFormat.allCases`), so a new one needs nothing here.
struct Command {

    static let usage = """
        usage: turnover <files…> --to <format> [--quality <quality>]
               turnover offers [--exact] <files…>

        Converts each file and saves the result next to it, with the same name and the new
        extension (numbered if that name is taken). Prints the path of each new file.
        Originals are never modified.

        `offers` lists the formats offered for the files, with estimated sizes and times,
        and converts nothing. With --exact it measures image sizes exactly (by encoding in
        memory, a few photos at most), as the ring does while you drag.

        formats: \(OutputFormat.allCases.map(\.rawValue).joined(separator: ", "))
        qualities (jpeg only): \(JPEGQuality.allCases.map { quality in
            "\(quality.rawValue) (\(quality.percent)%\(quality == .default ? ", the default" : ""))"
        }.joined(separator: ", "))
        """

    /// "best, high or small".
    private static let qualityChoices = JPEGQuality.allCases.map(\.rawValue).dropLast().joined(separator: ", ")
        + " or " + JPEGQuality.allCases.last!.rawValue

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
                guard let value = remaining.popFirst() else { throw UsageError(message: "--quality needs \(qualityChoices)") }
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
        guard let target = OutputFormat(conversion: format.lowercased())
        else { throw UsageError(message: "unknown format '\(format)'") }
        var preset = JPEGQuality.default
        if let quality {
            guard let chosen = JPEGQuality(rawValue: quality.lowercased())
            else { throw UsageError(message: "unknown quality '\(quality)' (use \(qualityChoices))") }
            guard target == .jpeg else { throw UsageError(message: "--quality only applies to jpeg") }
            preset = chosen
        }
        guard !files.isEmpty else { throw UsageError(message: "no files given") }
        return .convert(files: files, action: target.action(quality: preset))
    }
}
