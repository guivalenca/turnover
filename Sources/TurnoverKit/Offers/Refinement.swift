import Foundation

/// The background work behind one `LiveOffers`: quick estimates for the whole selection, then
/// the exact size of each image output, measured by encoding it in memory and remembered in the
/// cache.
struct Refinement: Sendable {
    let files: [URL]
    let inspection: Offers.Inspection
    let jpegQuality: JPEGQuality
    let cache: SizeCache
    /// Measuring waits while these run. The quick estimates don't: the ring needs them at once.
    let conversions: ConversionActivity?
    /// How many pixels may be measured exactly; the other images are scaled from them.
    let exactPixelBudget: Int

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


    /// What the quick estimates found, for measuring exactly afterwards.
    struct Start: Sendable {
        let candidates: [SourceFile]
        let pixels: [URL: Int]
        let measured: [URL: ImageSizes]
        let videos: [URL: VideoTime]
    }

    /// Works out the quick estimates and publishes them; returns what measuring needs.
    func quick(publish: @Sendable (Offers) async -> Void) async -> Start {
        let (known, _) = remembered()
        let unknown = ImageSizes.spread(images.filter { known[$0.url] == nil })
        async let quick = ImageSizes.quick(Array(unknown.prefix(ImageSizes.sampledImages)))
        async let pixelCounts = ImageSizes.pixelCounts(of: unknown)
        let videos = await VideoTime.of(inspection.files.filter { $0.kind == .video })
        let measured = await quick.merging(known) { quick, _ in quick }
        let pixels = await pixelCounts
        await publish(offers(ImageSizes.completing(measured, for: images, pixels: pixels), videos))
        return Start(candidates: unknown, pixels: pixels, measured: measured, videos: videos)
    }

    /// Measures exactly what `quick` left approximate, publishing the offers after each output.
    /// Stops at the next step when its task is cancelled: an encode in progress finishes, and
    /// nothing else starts.
    func exact(from start: Start, publish: @Sendable (Offers) async -> Void) async {
        await measureExactly(start.candidates, pixels: start.pixels, from: start.measured, videos: start.videos,
                             publish: publish)
    }

    /// Measures `candidates` exactly, in order, while they fit in `exactPixelBudget`, publishing
    /// the offers after each output. Waits whenever a conversion is running.
    private func measureExactly(_ candidates: [SourceFile], pixels: [URL: Int], from start: [URL: ImageSizes],
                                videos: [URL: VideoTime], publish: @Sendable (Offers) async -> Void) async {
        var measured = start
        var budget = exactPixelBudget
        var seen: Set<URL> = []
        for image in candidates where seen.insert(image.url).inserted {
            await conversions?.waitUntilIdle()
            guard !Task.isCancelled else { return }
            guard let count = pixels[image.url], count <= budget, let key = SizeCache.Key(image.url) else { continue }
            // Sizes remembered for some outputs already, from an earlier, interrupted measurement.
            let remembered = cache.sizes(for: key)?.sizes ?? [:]
            for (output, size) in remembered {
                measured[image.url, default: ImageSizes(pixels: count, sizes: [:])].sizes[output] = size
            }
            let outputs = ImageOutput.of(image).filter { remembered[$0] == nil }.sorted { rank($0) < rank($1) }
            guard !outputs.isEmpty,
                  let decoded = await blocking(.utility, { try? ImageConversion.Decoded(image.url) })
            else { continue }
            budget -= count
            // The decode read the whole file; if it changed meanwhile, these sizes belong to no key.
            let unchanged = SizeCache.Key(image.url) == key
            for output in outputs {
                await conversions?.waitUntilIdle()
                guard !Task.isCancelled else { return }
                guard let bytes = await blocking(.utility, {
                    ImageConversion.encodedSize(of: decoded, as: output.type, quality: output.encoderQuality)
                })
                else { break }
                if unchanged { cache.store(output, bytes: bytes, pixels: count, for: key) }
                measured[image.url, default: ImageSizes(pixels: count, sizes: [:])]
                    .sizes[output] = ImageSizes.Size(bytes: bytes, isExact: true)
                await publish(offers(ImageSizes.completing(measured, for: images, pixels: pixels, quick: start), videos))
            }
        }
    }

    /// The order outputs are measured in: the JPEG the ring shows first, since a JPEG takes
    /// milliseconds to encode and a PNG hundreds; then the other presets, for the ⌥ fan-out; then PNG.
    private func rank(_ output: ImageOutput) -> Int {
        switch output {
        case .jpeg(jpegQuality): 0
        case .jpeg: 1
        case .png: 2
        }
    }

    private func offers(_ images: [URL: ImageSizes], _ videos: [URL: VideoTime], pending: Set<URL> = []) -> Offers {
        Offers(files, inspection, jpegQuality: jpegQuality,
               estimates: Offers.Estimates(images: images, videos: videos, pending: pending))
    }
}
