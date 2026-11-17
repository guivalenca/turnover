import Foundation

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
                "\(saved.title): \(saved.reason.prefix(1).lowercased() + saved.reason.dropFirst())"
            } else {
                names(converted.map(\.output))
            }
            notices.append(Notice(kind: .converted, title: "Converted \(summary(of: converted))",
                                  body: body, files: converted.map(\.output)))
        } else if let saved = savedToDownloads(inDownloads) {
            notices.append(Notice(kind: .savedToDownloads, title: saved.title, body: saved.reason,
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
            notices.append(Notice(kind: .failed, title: "Couldn't convert \(only.file.lastPathComponent)",
                                  body: sentence(only.reason), files: []))
        } else if !failures.isEmpty {
            notices.append(Notice(kind: .failed, title: "Couldn't convert \(failures.count) files",
                                  body: failures.map(\.localizedDescription).joined(separator: "\n"), files: []))
        }
        return notices
    }

    /// "damaged or incomplete, …" as a sentence, for a notice whose title names the file.
    private static func sentence(_ reason: String) -> String {
        reason.prefix(1).uppercased() + reason.dropFirst()
    }

    /// "Saved photo.png to Downloads" and why, or nil when nothing went there.
    private static func savedToDownloads(_ results: [ConversionResult]) -> (title: String, reason: String)? {
        guard let first = results.first else { return nil }
        return results.count == 1
            ? ("Saved \(first.output.lastPathComponent) to Downloads",
               "The folder of \(first.source.lastPathComponent) is read-only.")
            : ("Saved \(results.count) files to Downloads", "The folders of the originals are read-only.")
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
        return groups.map { "\(count($0.count, $0.kind)) to \($0.format.name)" }.joined(separator: " and ")
    }

    /// "1 image", "2 videos", "3 files".
    private static func count(_ number: Int, _ kind: SourceFile.Kind) -> String {
        let noun = switch kind {
        case .image: "image"
        case .video: "video"
        case .unsupported: "file"
        }
        return "\(number) \(noun)\(number == 1 ? "" : "s")"
    }

    /// "a.mp4", "a.mp4 and b.mp4", or "a.mp4 and 2 more".
    private static func names(_ files: [URL]) -> String {
        let names = files.map(\.lastPathComponent)
        return switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: "\(names[0]) and \(names.count - 1) more"
        }
    }
}
