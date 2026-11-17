import Foundation

/// What Turnover can do with a selection of files: for each kind of file (images, videos), the
/// formats it can be converted to, and which files each format applies to.
///
/// The Finder menu shows one item per target; the ring shows one entry per target.
public struct Offers: Sendable, Hashable {
    /// Images first, then videos. A kind appears only if at least one format is offered for it.
    public let groups: [Group]

    /// Every offered format, in display order: the targets of each group in turn.
    public var targets: [Target] { groups.flatMap(\.targets) }

    /// The files no format applies to, in selection order, each with the reason: not an image
    /// or a video (with its type), already an MP4, or unreadable.
    public let skipped: [ConversionError]

    /// Why nothing can be converted, for a short hint, e.g. "notes.txt: not an image or a video
    /// (text)". Nil when something is offered.
    public var reason: String? {
        guard targets.isEmpty else { return nil }
        guard let first = skipped.first else { return "No files" }
        let more = skipped.count - 1
        return first.localizedDescription + (more == 0 ? "" : ", and \(more) more file\(more == 1 ? "" : "s")")
    }

    /// One kind of file in the selection, with the formats offered for it.
    public struct Group: Sendable, Hashable {
        /// `.image` or `.video`.
        public let kind: SourceFile.Kind
        /// Every file of this kind in the selection, in selection order.
        public let files: [URL]
        /// The formats offered, in display order (PNG before JPEG).
        public let targets: [Target]
    }

    /// One format offered for some of the selected files.
    public struct Target: Sendable, Hashable {
        public let format: OutputFormat
        /// The files this format applies to, in selection order. A file never appears in a
        /// target for its own format: a PNG is not offered PNG.
        public let files: [URL]
    }

    /// Inspects `files` by their contents and works out what is offered. It only sniffs each
    /// file's type, without decoding it, so it is quick enough to build a menu.
    public init(for files: [URL]) {
        var inspected: [SourceFile] = []
        var unreadable: [URL: ConversionError] = [:]
        for url in files {
            do { inspected.append(try SourceFile(url)) } catch {
                unreadable[url] = error as? ConversionError ?? .unreadable(url)
            }
        }
        let actions = OutputFormat.allCases.map { ($0, $0.action()) }
        groups = [SourceFile.Kind.image, .video].compactMap { kind in
            let members = inspected.filter { $0.kind == kind }
            let targets = actions.compactMap { format, action -> Target? in
                let fitting = members.filter(action.accepts)
                return fitting.isEmpty ? nil : Target(format: format, files: fitting.map(\.url))
            }
            return targets.isEmpty ? nil : Group(kind: kind, files: members.map(\.url), targets: targets)
        }
        let offered = Set(groups.flatMap(\.targets).flatMap(\.files))
        let refusals = Dictionary(inspected.map { file in
            // "Already an MP4" says more than "can't be converted to PNG".
            let reasons = actions.map { ConversionError.refusal(of: file, by: $0.1) }
            return (file.url, reasons.first { if case .alreadyInFormat = $0 { true } else { false } } ?? reasons[0])
        }, uniquingKeysWith: { first, _ in first })
        skipped = files.filter { !offered.contains($0) }.compactMap { unreadable[$0] ?? refusals[$0] }
    }
}
