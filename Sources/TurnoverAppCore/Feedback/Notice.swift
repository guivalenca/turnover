import Foundation
import TurnoverKit

/// A notification to post when a batch ends.
public struct Notice: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// A batch took long enough that its end is worth telling: "Converted 2 videos to MP4".
        case converted
        /// Some outputs went to Downloads because their original's folder is read-only.
        case savedToDownloads
        /// Some files couldn't be converted: they failed, or turned out not to fit their format.
        case failed
    }

    public var kind: Kind
    public var title: String
    public var body: String
    /// The new files Show in Finder selects. Empty when there is nothing to show.
    public var files: [URL]

    public init(kind: Kind, title: String, body: String, files: [URL]) {
        self.kind = kind
        self.title = title
        self.body = body
        self.files = files
    }
}

extension Notice {
    /// How long a batch takes before its end gets a notification.
    public static let slowBatch: Duration = .seconds(3)

    /// The notices for `batch`, which has ended after running for `duration`.
    @MainActor static func notices(for batch: Batch, took duration: Duration) -> [Notice] {
        let converted = batch.jobs.compactMap(\.result)
        let inDownloads = converted.filter(\.savedToDownloads)
        var notices: [Notice] = []
        if duration > slowBatch, !converted.isEmpty {
            let body = if let saved = savedToDownloads(inDownloads) {
                String(localized: "\(saved.title): \(saved.clause).", bundle: .appCore,
                       comment: "A slow batch's notice, when its new files went to Downloads: “Saved clip.mp4 to Downloads: the folder of clip.mov is read-only.”")
            } else {
                names(converted.map(\.output))
            }
            let title = String(localized: "Converted \(summary(of: converted))", bundle: .appCore,
                               comment: "A slow batch's notice: what it converted, “Converted 2 videos to MP4”.")
            notices.append(Notice(kind: .converted, title: title, body: body, files: converted.map(\.output)))
        } else if let saved = savedToDownloads(inDownloads) {
            notices.append(Notice(kind: .savedToDownloads, title: saved.title, body: saved.sentence,
                                  files: inDownloads.map(\.output)))
        }
        // The app only converts files offered for their format, so a file skipped here is one
        // whose contents didn't fit after all (a PNG named x.jpg was offered PNG by its
        // extension, say). That is as much a failure as a damaged file, and never silent.
        let failures = batch.jobs.compactMap { job -> ConversionError? in
            switch job.state {
            case .failed(let error), .skipped(let error): error
            default: nil
            }
        }
        if let only = failures.first, failures.count == 1 {
            let title = String(localized: "Couldn't convert \(only.file.lastPathComponent)", bundle: .appCore,
                               comment: "The notice for a file that failed: its name.")
            notices.append(Notice(kind: .failed, title: title, body: sentence(only.reason), files: []))
        } else if !failures.isEmpty {
            let title = String(localized: "Couldn't convert \(failures.count) files", bundle: .appCore,
                               comment: "The notice for several files that failed. Its body lists each one and why.")
            notices.append(Notice(kind: .failed, title: title,
                                  body: failures.map(\.localizedDescription).joined(separator: "\n"), files: []))
        }
        return notices
    }

    /// "damaged or incomplete, …" as a sentence, for a notice whose title names the file.
    private static func sentence(_ reason: String) -> String {
        reason.prefix(1).uppercased() + reason.dropFirst()
    }

    /// "Saved photo.png to Downloads" and why, as a sentence and as a clause to follow a colon;
    /// nil when nothing went there.
    private static func savedToDownloads(_ results: [ConversionResult]) -> (title: String, sentence: String, clause: String)? {
        guard let first = results.first else { return nil }
        guard results.count > 1 else {
            let (output, source) = (first.output.lastPathComponent, first.source.lastPathComponent)
            return (String(localized: "Saved \(output) to Downloads", bundle: .appCore,
                           comment: "The notice for a new file saved to Downloads: its name."),
                    String(localized: "The folder of \(source) is read-only.", bundle: .appCore,
                           comment: "Why a new file went to Downloads: the original's name."),
                    String(localized: "the folder of \(source) is read-only", bundle: .appCore,
                           comment: "Why a new file went to Downloads, after a colon: the original's name."))
        }
        return (String(localized: "Saved \(results.count) files to Downloads", bundle: .appCore,
                       comment: "The notice for new files saved to Downloads: how many."),
                String(localized: "The folders of the originals are read-only.", bundle: .appCore,
                       comment: "Why new files went to Downloads."),
                String(localized: "the folders of the originals are read-only", bundle: .appCore,
                       comment: "Why new files went to Downloads, after a colon."))
    }

    /// "2 videos to MP4", or "3 images to PNG and 1 video to MP4" for a mixed batch.
    private static func summary(of results: [ConversionResult]) -> String {
        var groups: [(kind: SourceFile.Kind, format: OutputFormat, count: Int)] = []
        for result in results {
            if let index = groups.firstIndex(where: { $0.kind == result.kind && $0.format == result.format }) {
                groups[index].count += 1
            } else {
                groups.append((result.kind, result.format, 1))
            }
        }
        return groups.map { converted($0.count, $0.kind, to: $0.format) }.reduce(nil, and) ?? ""
    }

    /// "1 image to PNG", "2 videos to MP4".
    private static func converted(_ count: Int, _ kind: SourceFile.Kind, to format: OutputFormat) -> String {
        let comment: StaticString = "Part of a slow batch's notice, after “Converted”: how many files, to which format."
        return switch kind {
        case .image: String(localized: "\(count) images to \(format.name)", bundle: .appCore, comment: comment)
        case .video: String(localized: "\(count) videos to \(format.name)", bundle: .appCore, comment: comment)
        case .unsupported: String(localized: "\(count) files to \(format.name)", bundle: .appCore, comment: comment)
        }
    }

    /// "a.mp4", "a.mp4 and b.mp4", or "a.mp4 and 2 more".
    private static func names(_ files: [URL]) -> String {
        let names = files.map(\.lastPathComponent)
        guard names.count > 2 else { return names.reduce(nil, and) ?? "" }
        return String(localized: "\(names[0]) and \(names.count - 1) more", bundle: .appCore,
                      comment: "A slow batch's notice: the first new file's name, and how many others.")
    }

    /// "a and b"; `b` alone when there's no `a` yet.
    private static func and(_ first: String?, _ second: String) -> String {
        guard let first else { return second }
        return String(localized: "\(first) and \(second)", bundle: .appCore,
                      comment: "Two things in a notice: “a.mp4 and b.mp4”, “2 images to JPEG and 1 video to MP4”.")
    }
}

extension Bundle {
    /// TurnoverAppCore's strings, from its Localizable.xcstrings.
    static let appCore = strings(of: "TurnoverAppCore")
}
