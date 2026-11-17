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
        /// The kind of file it converts: `.image` or `.video`.
        public let kind: SourceFile.Kind
        /// The files this format applies to, in selection order. A file never appears in a
        /// target for its own format: a PNG is not offered PNG.
        public let files: [URL]
        /// For JPEG, the preset the target converts with and `estimate` is for; nil otherwise.
        public let quality: JPEGQuality?
        /// For all of `files` together. Nil from `init(for:)`, which doesn't estimate, or when no
        /// file could be estimated.
        public let estimate: Estimate?
        /// For JPEG with estimates, every preset with its own estimate, from Best to Small, for
        /// the ⌥ fan-out. Empty otherwise.
        public let presets: [Preset]

        /// The action that converts `files` to this target's format.
        public var action: any ConversionAction { format.action(quality: quality ?? .default) }

        /// The Finder menu item: the format and how many files it converts, e.g. "PNG (3 images)".
        public var menuTitle: String {
            let noun = kind == .video ? "video" : "image"
            return "\(format.name) (\(files.count) \(noun)\(files.count == 1 ? "" : "s"))"
        }
    }

    /// One JPEG quality and its estimate.
    public struct Preset: Sendable, Hashable {
        public let quality: JPEGQuality
        public let estimate: Estimate
    }

    /// Inspects `files` by their contents and works out what is offered. It only sniffs each
    /// file's type, without decoding it, so it is quick enough to build a menu.
    public init(for files: [URL]) {
        self.init(files, Inspection(files), jpegQuality: .default, estimates: nil)
    }

    /// Works out what is offered from each file's declared type (`URLResourceValues.contentType`,
    /// mostly from its extension), without opening the files. This is for the sandboxed Finder
    /// extension, which may read the selection's metadata but not its contents. A file whose
    /// extension doesn't match its contents is skipped later, when the app converts it.
    public init(declaredTypesOf files: [URL]) {
        self.init(files, Inspection(declaredTypesOf: files), jpegQuality: .default, estimates: nil)
    }

    /// The same offers, with an estimate for each target: output sizes for images (each JPEG
    /// preset too, with `jpegQuality` the one JPEG uses), and time for videos.
    public init(estimating files: [URL], jpegQuality: JPEGQuality = .default) async {
        let inspection = Inspection(files)
        async let images = ImageSizes.of(inspection.files.filter { $0.kind == .image })
        async let videos = withTaskGroup(of: (URL, VideoTime?).self) { group in
            for file in inspection.files where file.kind == .video {
                group.addTask { (file.url, await VideoTime(of: file.url)) }
            }
            return await group.reduce(into: [URL: VideoTime]()) { $0[$1.0] = $1.1 }
        }
        self.init(files, inspection, jpegQuality: jpegQuality,
                  estimates: Estimates(images: await images, videos: await videos))
    }

    /// Every file of a selection, inspected by content.
    private struct Inspection {
        var files: [SourceFile] = []
        var unreadable: [URL: ConversionError] = [:]

        init(_ urls: [URL]) {
            for url in urls {
                do { files.append(try SourceFile(url)) } catch {
                    unreadable[url] = error as? ConversionError ?? .unreadable(url)
                }
            }
        }

        init(declaredTypesOf urls: [URL]) {
            for url in urls {
                if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
                    files.append(SourceFile(url, declaredType: type))
                } else {
                    unreadable[url] = .unreadable(url)
                }
            }
        }
    }

    /// What is known about each file's output. Files that couldn't be measured (damaged ones)
    /// are left out of the estimates, though they stay in their targets: converting them reports
    /// the failure.
    struct Estimates {
        var images: [URL: ImageSizes]
        var videos: [URL: VideoTime]

        func estimate(_ format: OutputFormat, quality: JPEGQuality, of files: [URL]) -> Estimate? {
            if format == .mp4 { return VideoTime.estimate(files.compactMap { videos[$0] }) }
            let sizes = files.compactMap { images[$0] }
            guard !sizes.isEmpty else { return nil }
            return .size(sizes.reduce(0) { $0 + $1.bytes(as: format, quality: quality) })
        }
    }

    private init(_ files: [URL], _ inspection: Inspection, jpegQuality: JPEGQuality, estimates: Estimates?) {
        let inspected = inspection.files
        let actions = OutputFormat.allCases.map { ($0, $0.action()) }
        groups = [SourceFile.Kind.image, .video].compactMap { kind in
            let members = inspected.filter { $0.kind == kind }
            let targets = actions.compactMap { format, action -> Target? in
                let fitting = members.filter(action.accepts).map(\.url)
                guard !fitting.isEmpty else { return nil }
                let quality = format == .jpeg ? jpegQuality : nil
                let presets = format != .jpeg ? [] : JPEGQuality.allCases.compactMap { preset in
                    estimates?.estimate(format, quality: preset, of: fitting).map { Preset(quality: preset, estimate: $0) }
                }
                return Target(format: format, kind: kind, files: fitting, quality: quality,
                              estimate: estimates?.estimate(format, quality: jpegQuality, of: fitting), presets: presets)
            }
            return targets.isEmpty ? nil : Group(kind: kind, files: members.map(\.url), targets: targets)
        }
        let offered = Set(groups.flatMap(\.targets).flatMap(\.files))
        let refusals = Dictionary(inspected.map { file in
            // "Already an MP4" says more than "can't be converted to PNG".
            let reasons = actions.map { ConversionError.refusal(of: file, by: $0.1) }
            return (file.url, reasons.first { if case .alreadyInFormat = $0 { true } else { false } } ?? reasons[0])
        }, uniquingKeysWith: { first, _ in first })
        skipped = files.filter { !offered.contains($0) }.compactMap { inspection.unreadable[$0] ?? refusals[$0] }
    }
}
