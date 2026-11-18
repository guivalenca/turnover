import Foundation
import TurnoverKit

/// `turnover offers [--exact] <files…>`: the formats Turnover offers for the files, as the Finder
/// menu and the ring would, with their estimates. Converts nothing. `--exact` waits for the
/// refined estimates the ring ends up showing: exact sizes for a few photos, the rest scaled.
///
/// Exit codes: 0 when anything is offered, 1 when nothing is, 64 (EX_USAGE) for a bad command line.
enum OffersCommand {
    static let usage = "usage: turnover offers [--exact] <files…>"

    static func run(_ arguments: [String]) async -> Int32 {
        let files: [String], exact: Bool
        do {
            guard !arguments.contains(where: { $0 == "-h" || $0 == "--help" }) else {
                print(usage)
                return 0
            }
            (files, exact) = try parse(arguments)
        } catch {
            FileHandle.standardError.write(Data("turnover: \(error.message)\n\(usage)\n".utf8))
            return 64
        }
        let urls = files.map { URL(fileURLWithPath: $0).absoluteURL.standardizedFileURL }
        let offers = exact ? await refined(urls) : await Offers(estimating: urls)
        print(render(offers), terminator: "")
        return offers.targets.isEmpty ? 1 : 0
    }

    @MainActor
    private static func refined(_ files: [URL]) async -> Offers {
        let live = await Estimator().estimate(files)
        await live.waitUntilFinished()
        return live.offers
    }

    private static func parse(_ arguments: [String]) throws(Command.UsageError) -> (files: [String], exact: Bool) {
        var files: [String] = []
        var exact = false
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            if argument == "--exact" {
                exact = true
            } else if argument == "--" {
                files.append(contentsOf: remaining)
                remaining = []
            } else if argument.hasPrefix("-") && argument != "-" {
                throw Command.UsageError(message: "unknown option \(argument)")
            } else {
                files.append(argument)
            }
        }
        guard !files.isEmpty else { throw Command.UsageError(message: "no files given") }
        return (files, exact)
    }

    /// For example:
    ///
    ///     Images (2 files)
    ///       PNG   1 file   ~45 KB
    ///       JPEG  2 files  Best ~61 KB, High ~28 KB (default), Small ~19 KB
    ///     Videos (1 file)
    ///       MP4   1 file   Instant
    ///     Skipped
    ///       notes.txt: not an image or a video (text)
    static func render(_ offers: Offers) -> String {
        var lines: [String] = []
        for group in offers.groups {
            lines.append("\(group.kind == .video ? "Videos" : "Images") (\(count(group.files)))")
            for target in group.targets {
                lines.append("  " + column(target.format.name, 6) + column(count(target.files), 9) + estimates(target))
            }
        }
        if !offers.skipped.isEmpty {
            lines.append("Skipped")
            lines += offers.skipped.map { "  " + $0.localizedDescription }
        }
        return lines.map { $0 + "\n" }.joined()
    }

    /// JPEG lists every preset and marks the one it uses; the others have one estimate.
    private static func estimates(_ target: Offers.Target) -> String {
        guard !target.presets.isEmpty else { return target.estimate?.label ?? "no estimate" }
        return target.presets.map { preset in
            "\(preset.quality.name) \(preset.estimate.label)" + (preset.quality == target.quality ? " (default)" : "")
        }.joined(separator: ", ")
    }

    private static func count(_ files: [URL]) -> String {
        files.count == 1 ? "1 file" : "\(files.count) files"
    }

    private static func column(_ text: String, _ width: Int) -> String {
        text + String(repeating: " ", count: max(1, width - text.count))
    }
}
