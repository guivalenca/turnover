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
    /// The images whose every output the cache remembered when the work began.
    let known: [URL: ImageSizes]

    /// Inspects `files` and checks the cache, on a dispatch queue: both read the files.
    static func start(_ files: [URL], jpegQuality: JPEGQuality, cache: SizeCache, conversions: ConversionActivity?,
                      exactPixelBudget: Int) async -> Refinement {
        await blocking(.userInitiated) {
            let inspection = Offers.Inspection(files)
            return Refinement(files: files, inspection: inspection, jpegQuality: jpegQuality, cache: cache,
                              conversions: conversions, exactPixelBudget: exactPixelBudget,
                              known: remembered(inspection.files.filter { $0.kind == .image }, in: cache))
        }
    }

    /// The images whose every output `cache` remembers. Reads each file's size and date.
    private static func remembered(_ images: [SourceFile], in cache: SizeCache) -> [URL: ImageSizes] {
        var known: [URL: ImageSizes] = [:]
        for image in images {
            guard let key = SizeCache.Key(image.url), let sizes = cache.sizes(for: key),
                  ImageOutput.of(image).allSatisfy({ sizes.sizes[$0] != nil })
            else { continue }
            known[image.url] = sizes
        }
        return known
    }

    /// The images of the selection.
    var images: [SourceFile] { inspection.files.filter { $0.kind == .image } }

    /// The offers before any work: exact for remembered images, without estimates otherwise.
    func initialOffers() -> Offers {
        let pending = Set(images.map(\.url)).subtracting(known.keys)
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
        let unknown = ImageSizes.spread(images.filter { known[$0.url] == nil })
        async let quick = ImageSizes.quick(Array(unknown.prefix(ImageSizes.sampledImages)))
        async let pixelCounts = blocking(.userInitiated) { ImageSizes.pixelCounts(of: unknown) }
        let videos = await VideoTime.of(inspection.files.filter { $0.kind == .video })
        let measured = await quick.merging(known) { quick, _ in quick }
        let pixels = await pixelCounts
        await publish(offers(ImageSizes.completing(measured, for: images, pixels: pixels), videos))
        return Start(candidates: unknown, pixels: pixels, measured: measured, videos: videos)
    }

    /// Measures exactly what `quick` left approximate: its candidates in order, while they fit
    /// in `exactPixelBudget`, publishing the offers after each output. Waits whenever a
    /// conversion is running. Stops at the next step when its task is cancelled: an encode in
    /// progress finishes, and nothing else starts.
    func exact(from start: Start, publish: @Sendable (Offers) async -> Void) async {
        var measured = start.measured
        var budget = exactPixelBudget
        var seen: Set<URL> = []
        for image in start.candidates where seen.insert(image.url).inserted {
            await conversions?.waitUntilIdle()
            guard !Task.isCancelled else { return }
            guard let count = start.pixels[image.url], count <= budget,
                  let key = await blocking(.utility, { SizeCache.Key(image.url) })
            else { continue }
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
            let unchanged = await blocking(.utility, { SizeCache.Key(image.url) }) == key
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
                await publish(offers(ImageSizes.completing(measured, for: images, pixels: start.pixels,
                                                           quick: start.measured), start.videos))
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
