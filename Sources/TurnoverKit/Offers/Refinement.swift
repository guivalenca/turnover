import Foundation

/// The background work behind one `LiveOffers`: quick estimates for the whole selection, then
/// the exact size of each image output, measured by encoding it in memory.
struct Refinement: Sendable {
    let files: [URL]
    let inspection: Offers.Inspection
    let jpegQuality: JPEGQuality

    /// Calls `publish` with the quick offers, then again each time an exact size is known.
    func run(publish: @Sendable (Offers) async -> Void) async {
        let images = inspection.files.filter { $0.kind == .image }
        async let quickSizes = ImageSizes.of(images)
        let videos = await VideoTime.of(inspection.files.filter { $0.kind == .video })
        var sizes = await quickSizes
        await publish(offers(sizes, videos))

        for image in images {
            guard let decoded = try? ImageConversion.Decoded(image.url) else { continue }
            for output in ImageOutput.of(image) {
                guard let bytes = ImageConversion.encodedSize(of: decoded, as: output.type, quality: output.encoderQuality)
                else { break }
                sizes[image.url, default: ImageSizes(pixels: decoded.image.width * decoded.image.height, sizes: [:])]
                    .sizes[output] = ImageSizes.Size(bytes: bytes, isExact: true)
                await publish(offers(sizes, videos))
            }
        }
    }

    private func offers(_ images: [URL: ImageSizes], _ videos: [URL: VideoTime]) -> Offers {
        Offers(files, inspection, jpegQuality: jpegQuality, estimates: Offers.Estimates(images: images, videos: videos))
    }
}
