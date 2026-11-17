import Foundation

/// The background work behind one `LiveOffers`: quick estimates for the whole selection, then
/// the exact size of each image output, measured by encoding it in memory and remembered in the
/// cache.
struct Refinement: Sendable {
    let files: [URL]
    let inspection: Offers.Inspection
    let jpegQuality: JPEGQuality
    let cache: SizeCache

    /// The images of the selection.
    var images: [SourceFile] { inspection.files.filter { $0.kind == .image } }

    /// What the cache already knows, before any work: the images whose every output is
    /// remembered, and the other images, still pending.
    func remembered() -> (known: [URL: ImageSizes], pending: Set<URL>) {
        var known: [URL: ImageSizes] = [:]
        for image in images {
            guard let key = SizeCache.Key(image.url), let sizes = cache.sizes(for: key),
                  ImageOutput.of(image).allSatisfy({ sizes.sizes[$0] != nil })
            else { continue }
            known[image.url] = sizes
        }
        return (known, Set(images.map(\.url)).subtracting(known.keys))
    }

    /// The offers before any work: exact for remembered images, without estimates otherwise.
    func initialOffers() -> Offers {
        let (known, pending) = remembered()
        return offers(known, [:], pending: pending.union(inspection.files.filter { $0.kind == .video }.map(\.url)))
    }

    /// Calls `publish` with the quick offers, then again each time an exact size is known.
    func run(publish: @Sendable (Offers) async -> Void) async {
        let (known, _) = remembered()
        async let quickSizes = ImageSizes.of(images, known: known)
        let videos = await VideoTime.of(inspection.files.filter { $0.kind == .video })
        var sizes = await quickSizes
        await publish(offers(sizes, videos))

        for image in images where known[image.url] == nil {
            guard let key = SizeCache.Key(image.url) else { continue }
            // Sizes remembered for some outputs already, from an earlier, interrupted measurement.
            let remembered = cache.sizes(for: key)?.sizes ?? [:]
            for (output, size) in remembered { sizes[image.url]?.sizes[output] = size }
            let outputs = ImageOutput.of(image).filter { remembered[$0] == nil }
            guard !outputs.isEmpty, let decoded = try? ImageConversion.Decoded(image.url) else { continue }
            // The decode read the whole file; if it changed meanwhile, these sizes belong to no key.
            let unchanged = SizeCache.Key(image.url) == key
            let pixels = decoded.image.width * decoded.image.height
            for output in outputs {
                guard let bytes = ImageConversion.encodedSize(of: decoded, as: output.type, quality: output.encoderQuality)
                else { break }
                if unchanged { cache.store(output, bytes: bytes, pixels: pixels, for: key) }
                sizes[image.url, default: ImageSizes(pixels: pixels, sizes: [:])]
                    .sizes[output] = ImageSizes.Size(bytes: bytes, isExact: true)
                await publish(offers(sizes, videos))
            }
        }
    }

    private func offers(_ images: [URL: ImageSizes], _ videos: [URL: VideoTime], pending: Set<URL> = []) -> Offers {
        Offers(files, inspection, jpegQuality: jpegQuality,
               estimates: Offers.Estimates(images: images, videos: videos, pending: pending))
    }
}
