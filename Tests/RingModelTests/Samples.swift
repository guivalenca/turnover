import Foundation
import RingModel
import TurnoverKit

/// Dragged files for ring tests. Nothing is read from disk: the ring only sees offers.
enum Sample {
    static let photo = URL(fileURLWithPath: "/Users/me/Pictures/IMG_0001.heic")
    static let photo2 = URL(fileURLWithPath: "/Users/me/Pictures/IMG_0002.heic")
    static let screenshot = URL(fileURLWithPath: "/Users/me/Desktop/Screenshot.png")
    static let movie = URL(fileURLWithPath: "/Users/me/Movies/IMG_0003.mov")
    static let mp4 = URL(fileURLWithPath: "/Users/me/Movies/IMG_0004.mp4")
    static let lease = URL(fileURLWithPath: "/Users/me/Documents/lease.pdf")

    /// Offers for images that aren't PNGs or JPEGs (HEICs, say): PNG and JPEG.
    /// `presets`: each JPEG quality's estimate, for the ⌥ fan-out.
    static func images(_ files: [URL], png: Estimate? = nil, jpeg: Estimate? = nil,
                       jpegQuality: JPEGQuality = .default, presets: [JPEGQuality: Estimate] = [:]) -> Offers {
        Offers(groups: [.init(kind: .image, files: files, targets: [
            .init(format: .png, kind: .image, files: files, estimate: png),
            .init(format: .jpeg, kind: .image, files: files, quality: .jpeg(jpegQuality), estimate: jpeg,
                  presets: JPEGQuality.allCases.compactMap { quality in
                      presets[quality].map { Offers.Preset(quality: .jpeg(quality), estimate: $0) }
                  }),
        ])])
    }

    /// Offers for PNGs: JPEG only.
    static func pngs(_ files: [URL], jpeg: Estimate? = nil) -> Offers {
        Offers(groups: [.init(kind: .image, files: files, targets: [
            .init(format: .jpeg, kind: .image, files: files, quality: .jpeg(.default), estimate: jpeg),
        ])])
    }

    /// Offers for images that aren't PNGs or JPEGs and movies dragged together.
    static func mixed(_ images: [URL], _ movies: [URL], png: Estimate? = nil, jpeg: Estimate? = nil,
                      mp4: Estimate? = nil) -> Offers {
        Offers(groups: Sample.images(images, png: png, jpeg: jpeg).groups + Sample.movies(movies, mp4: mp4).groups)
    }

    /// Offers for PNGs and movies dragged together.
    static func mixed(pngs: [URL], _ movies: [URL]) -> Offers {
        Offers(groups: Sample.pngs(pngs).groups + Sample.movies(movies).groups)
    }

    /// A WebP dragged out of a web page, staged in a temporary folder.
    static let webImage = URL(fileURLWithPath: "/tmp/Turnover-dragged/mountain-lake.webp")

    /// Offers for an image dragged out of a web page: the formats that aren't its own, then
    /// Original, and what the image is.
    static func webImage(typeName: String = "WebP", formats: [OutputFormat] = [.png, .jpeg], width: Int? = 1600,
                         height: Int? = 1067, png: Estimate? = nil, jpeg: Estimate? = nil,
                         presets: [JPEGQuality: Estimate] = [:], original: Estimate? = .exactSize(212_000)) -> Offers {
        let converted = Sample.images([webImage], png: png, jpeg: jpeg, presets: presets).groups[0].targets
            .filter { formats.contains($0.format) }
        return Offers(groups: [.init(kind: .image, files: [webImage], targets: converted + [
            .init(format: .original, kind: .image, files: [webImage], estimate: original),
        ])], original: .init(typeName: typeName, width: width, height: height))
    }

    /// Offers for movies: MP4.
    static func movies(_ files: [URL], mp4: Estimate? = nil) -> Offers {
        Offers(groups: [.init(kind: .video, files: files, targets: [
            .init(format: .mp4, kind: .video, files: files, estimate: mp4),
        ])])
    }

    /// Offers for MP4s: a smaller one, at each quality's size.
    static func mp4s(_ files: [URL], presets: [VideoQuality: Int] = [:]) -> Offers {
        Offers(groups: [.init(kind: .video, files: files, targets: [
            .init(format: .smaller, kind: .video, files: files, quality: .video(.default),
                  estimate: presets[.default].map(Estimate.size),
                  presets: VideoQuality.allCases.compactMap { quality in
                      presets[quality].map { Offers.Preset(quality: .video(quality), estimate: .size($0)) }
                  }),
        ])])
    }
}

extension RingModel {
    /// A ring opened by ⇧ during a drag whose offers are already known.
    static func opened(with offers: Offers, restDelay: TimeInterval = 0.5) -> RingModel {
        var ring = RingModel(restDelay: restDelay)
        ring.send(.dragStarted(shiftDown: false))
        ring.send(.offers(offers))
        ring.send(.shift(down: true))
        return ring
    }
}
