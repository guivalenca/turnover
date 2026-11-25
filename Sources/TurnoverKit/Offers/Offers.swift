import Foundation
import ImageIO

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
    /// or a video (with its type), or unreadable.
    public let skipped: [ConversionError]

    /// What the lone image of offers that include Original is, for the ring's centre: an image
    /// dragged out of a web page says "WebP, 1600 × 1067" there. Nil for files on disk.
    public let original: Original?

    /// Why nothing can be converted, for a short hint, e.g. "notes.txt: not an image or a video
    /// (text)". Nil when something is offered.
    public var reason: String? {
        guard targets.isEmpty else { return nil }
        guard let first = skipped.first else {
            return String(localized: "No files", bundle: .turnoverKit, comment: "Why nothing can be converted: nothing was dragged.")
        }
        let more = skipped.count - 1
        guard more > 0 else { return first.localizedDescription }
        return String(localized: "\(first.localizedDescription), and \(more) more files", bundle: .turnoverKit,
                      comment: "Why nothing can be converted: the first file's reason, then how many other files can't be either.")
    }

    /// One kind of file in the selection, with the formats offered for it.
    public struct Group: Sendable, Hashable {
        /// `.image` or `.video`.
        public let kind: SourceFile.Kind
        /// Every file of this kind in the selection, in selection order.
        public let files: [URL]
        /// The formats offered, in display order (PNG before JPEG).
        public let targets: [Target]

        /// A group as given, for previews and tests; `Offers(for:)` and its siblings work groups out.
        public init(kind: SourceFile.Kind, files: [URL], targets: [Target]) {
            self.kind = kind
            self.files = files
            self.targets = targets
        }
    }

    /// One format offered for some of the selected files.
    public struct Target: Sendable, Hashable {
        public let format: OutputFormat
        /// The kind of file it converts: `.image` or `.video`.
        public let kind: SourceFile.Kind
        /// The files this format applies to, in selection order. A file never appears in a
        /// target for its own format: a PNG is not offered PNG.
        public let files: [URL]
        /// For JPEG and a smaller MP4, the quality the target converts with and `estimate` is for;
        /// nil otherwise.
        public let quality: Quality?
        /// For all of `files` together. Nil from `init(for:)`, which doesn't estimate, or when no
        /// file could be estimated.
        public let estimate: Estimate?
        /// For JPEG and a smaller MP4 with estimates, every quality with its own estimate, from
        /// the largest to the smallest, for the fan-out. Empty otherwise.
        public let presets: [Preset]

        /// The action that converts `files` to this target's format.
        public var action: any ConversionAction { format.action(quality: quality) }

        /// A target as given, for previews and tests; `Offers(for:)` and its siblings work targets out.
        public init(format: OutputFormat, kind: SourceFile.Kind, files: [URL], quality: Quality? = nil,
                    estimate: Estimate? = nil, presets: [Preset] = []) {
            self.format = format
            self.kind = kind
            self.files = files
            self.quality = quality
            self.estimate = estimate
            self.presets = presets
        }

        /// The Finder menu item: the format and how many files it converts, e.g. "PNG (3 images)".
        public var menuTitle: String {
            let count = files.count
            return kind == .video
                ? String(localized: "\(format.name) (\(count) videos)", bundle: .turnoverKit,
                         comment: "A Finder menu item: the format, and how many videos it converts.")
                : String(localized: "\(format.name) (\(count) images)", bundle: .turnoverKit,
                         comment: "A Finder menu item: the format, and how many images it converts.")
        }
    }

    /// What an image that can be saved as it is, is.
    public struct Original: Sendable, Hashable {
        /// Its format's short name: "WebP", "AVIF", "JPEG".
        public let typeName: String
        /// Its size in pixels, upright; nil when its header can't be read.
        public let width: Int?
        public let height: Int?

        public init(typeName: String, width: Int? = nil, height: Int? = nil) {
            self.typeName = typeName
            self.width = width
            self.height = height
        }
    }

    /// One quality and its estimate.
    public struct Preset: Sendable, Hashable {
        public let quality: Quality
        public let estimate: Estimate

        public init(quality: Quality, estimate: Estimate) {
            self.quality = quality
            self.estimate = estimate
        }
    }

    /// Offers as given, for previews and tests (the ring model's): `init(for:)` and its siblings
    /// work them out from files.
    public init(groups: [Group], skipped: [ConversionError] = [], original: Original? = nil) {
        self.groups = groups
        self.skipped = skipped
        self.original = original
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
    /// preset too, with `jpegQuality` the one JPEG uses) and for smaller MP4s, and time for MP4.
    public init(estimating files: [URL], jpegQuality: JPEGQuality = .default) async {
        let inspection = await blocking(.userInitiated) { Inspection(files) }
        async let images = ImageSizes.of(inspection.files.filter { $0.kind == .image })
        async let videos = VideoTime.of(inspection.files.filter { $0.kind == .video })
        self.init(files, inspection, jpegQuality: jpegQuality,
                  estimates: Estimates(images: await images, videos: await videos))
    }

    /// Every file of a selection, inspected by content.
    struct Inspection: Sendable {
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
    struct Estimates: Sendable {
        var images: [URL: ImageSizes]
        var videos: [URL: VideoTime]
        /// Images not estimated yet. A target with any of them has no estimate: a total of the
        /// others would look complete.
        var pending: Set<URL> = []

        func estimate(_ format: OutputFormat, quality: Quality?, of files: [URL]) -> Estimate? {
            if case .video(let quality) = quality {
                let sizes = files.compactMap { videos[$0]?.smaller[quality] }
                return sizes.isEmpty ? nil : .size(sizes.reduce(0, +))
            }
            guard let output = ImageOutput(format, quality: quality) else {
                return VideoTime.estimate(files.compactMap { videos[$0] })
            }
            guard pending.isDisjoint(with: files) else { return nil }
            let sizes = files.compactMap { images[$0]?.sizes[output] }
            guard !sizes.isEmpty else { return nil }
            let total = sizes.reduce(0) { $0 + $1.bytes }
            // Exact only if every file was measured: one that couldn't be may still convert.
            return sizes.count == files.count && sizes.allSatisfy(\.isExact) ? .exactSize(total) : .size(total)
        }
    }

    /// What saving each image as it is gives: a file of its size now. For a lone image, what it
    /// is too.
    struct Originals: Sendable {
        var bytes: [URL: Int] = [:]
        var facts: Original?

        /// Reads each image's size, and a lone image's header.
        init(_ images: [SourceFile]) {
            for image in images {
                bytes[image.url] = (try? image.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            }
            guard images.count == 1, let image = images.first else { return }
            let header = ImageHeader(image.url)
            // Orientations 5 to 8 are stored on their side.
            let turned = (header?.properties[kCGImagePropertyOrientation] as? Int ?? 1) >= 5
            facts = Original(typeName: image.typeName,
                             width: turned ? header?.height : header?.width,
                             height: turned ? header?.width : header?.height)
        }
    }

    /// With `originals`, the images are offered Original too, after the formats: every image,
    /// whatever its own format.
    init(_ files: [URL], _ inspection: Inspection, jpegQuality: JPEGQuality, estimates: Estimates?,
         originals: Originals? = nil) {
        let inspected = inspection.files
        let actions = OutputFormat.allCases.map { ($0, $0.action()) }
        groups = [SourceFile.Kind.image, .video].compactMap { kind in
            let members = inspected.filter { $0.kind == kind }
            var targets = actions.compactMap { format, action -> Target? in
                let fitting = members.filter(action.accepts).map(\.url)
                guard !fitting.isEmpty else { return nil }
                let quality: Quality? = switch format {
                case .jpeg: .jpeg(jpegQuality)
                case .smaller: .video(.default)
                case .png, .mp4, .original: nil
                }
                let presets = format.qualities.compactMap { preset in
                    estimates?.estimate(format, quality: preset, of: fitting).map { Preset(quality: preset, estimate: $0) }
                }
                return Target(format: format, kind: kind, files: fitting, quality: quality,
                              estimate: estimates?.estimate(format, quality: quality, of: fitting), presets: presets)
            }
            if kind == .image, let originals, !members.isEmpty {
                let images = members.map(\.url)
                let sizes = images.compactMap { originals.bytes[$0] }
                targets.append(Target(format: .original, kind: .image, files: images,
                                      estimate: sizes.count == images.count ? .exactSize(sizes.reduce(0, +)) : nil))
            }
            return targets.isEmpty ? nil : Group(kind: kind, files: members.map(\.url), targets: targets)
        }
        original = groups.first { $0.kind == .image }?.files.count == 1 ? originals?.facts : nil
        let offered = Set(groups.flatMap(\.targets).flatMap(\.files))
        let refusals = Dictionary(inspected.map { file in
            // "Already an MP4" says more than "can't be converted to PNG".
            let reasons = actions.map { ConversionError.refusal(of: file, by: $0.1) }
            return (file.url, reasons.first { if case .alreadyInFormat = $0 { true } else { false } } ?? reasons[0])
        }, uniquingKeysWith: { first, _ in first })
        skipped = files.filter { !offered.contains($0) }.compactMap { inspection.unreadable[$0] ?? refusals[$0] }
    }
}
