import Foundation
import TurnoverKit

extension RingModel {
    /// One format to convert some of the dragged files to: what a drop converts, per kind.
    public struct Choice: Sendable, Hashable {
        /// `.image` or `.video`.
        public let kind: SourceFile.Kind
        public let format: OutputFormat
        /// The quality to convert with; nil for formats without any.
        public let quality: Quality?
        /// The files it converts, in drag order.
        public let files: [URL]

        /// The action that converts `files`. Run every choice of a drop as one batch:
        /// `runner.run(choices.flatMap(\\.files), to: choices.map(\\.action))`.
        public var action: any ConversionAction { format.action(quality: quality) }

        public init(kind: SourceFile.Kind, format: OutputFormat, quality: Quality? = nil, files: [URL]) {
            self.kind = kind
            self.format = format
            self.quality = quality
            self.files = files
        }

        /// A target as offered: JPEG and a smaller MP4 at the quality they were offered with
        /// (the default).
        init(_ target: Offers.Target) {
            self.init(kind: target.kind, format: target.format, quality: target.quality, files: target.files)
        }
    }
}
