import Foundation
import Observation

/// Works out offers for live UI (the ring): quick estimates first, then exact image sizes,
/// measured in the background by encoding the real outputs in memory.
///
/// Keep one for the app.
@MainActor
public final class Estimator {
    public init() {}

    /// Starts estimating `files` and returns at once. The offers sharpen as the work goes on.
    public func estimate(_ files: [URL], jpegQuality: JPEGQuality = .default) -> LiveOffers {
        LiveOffers(files, jpegQuality: jpegQuality)
    }
}

/// The offers for one selection, with estimates that improve while you watch: quick guesses
/// first, then exact sizes as they are measured.
@MainActor @Observable
public final class LiveOffers {
    /// The latest offers. Targets and skipped files never change; estimates fill in and sharpen.
    public private(set) var offers: Offers
    /// True once the estimates won't change any more.
    public private(set) var isFinished = false

    @ObservationIgnored private var work: Task<Void, Never>?

    init(_ files: [URL], jpegQuality: JPEGQuality) {
        let inspection = Offers.Inspection(files)
        offers = Offers(files, inspection, jpegQuality: jpegQuality, estimates: nil)
        work = Task.detached(priority: .utility) { [weak self] in
            var images: [URL: ImageSizes] = [:]
            for file in inspection.files where file.kind == .image {
                var sizes: [ImageOutput: ImageSizes.Size] = [:]
                try? ImageSizes.measureExactly(file, ImageOutput.of(file)) { output, bytes in
                    sizes[output] = ImageSizes.Size(bytes: bytes, isExact: true)
                }
                if !sizes.isEmpty { images[file.url] = ImageSizes(pixels: 0, sizes: sizes) }
            }
            var videos: [URL: VideoTime] = [:]
            for file in inspection.files where file.kind == .video {
                videos[file.url] = await VideoTime(of: file.url)
            }
            let offers = Offers(files, inspection, jpegQuality: jpegQuality,
                                estimates: Offers.Estimates(images: images, videos: videos))
            await self?.publish(offers)
        }
    }

    /// Waits until the estimates won't change any more.
    public func waitUntilFinished() async {
        await work?.value
        isFinished = true
    }

    private func publish(_ offers: Offers) {
        self.offers = offers
    }
}
