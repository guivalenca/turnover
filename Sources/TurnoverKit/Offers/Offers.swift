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
        let inspected = files.compactMap { try? SourceFile($0) }
        groups = [SourceFile.Kind.image, .video].compactMap { kind in
            let members = inspected.filter { $0.kind == kind }
            let targets = OutputFormat.allCases.compactMap { format -> Target? in
                let action = format.action()
                let fitting = members.filter(action.accepts)
                return fitting.isEmpty ? nil : Target(format: format, files: fitting.map(\.url))
            }
            return targets.isEmpty ? nil : Group(kind: kind, files: members.map(\.url), targets: targets)
        }
    }
}
