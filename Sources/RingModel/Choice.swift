import Foundation
import TurnoverKit

extension RingModel {
    /// One format to convert some of the dragged files to: what a drop converts, per kind.
    public struct Choice: Sendable, Hashable {
        /// `.image` or `.video`.
        public let kind: SourceFile.Kind
        public let format: OutputFormat
        /// The JPEG preset to convert with; nil for other formats.
        public let quality: JPEGQuality?
        /// The files it converts, in drag order.
        public let files: [URL]

        /// The action that converts `files`. Run every choice of a drop as one batch:
        /// `runner.run(choices.flatMap(\\.files), to: choices.map(\\.action))`.
        public var action: any ConversionAction { format.action(quality: quality ?? .default) }
    }
}
