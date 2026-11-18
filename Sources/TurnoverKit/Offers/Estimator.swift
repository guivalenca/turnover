import Foundation
import Observation

/// Works out offers for live UI (the ring): quick estimates first, then exact image sizes,
/// measured in the background by encoding the real outputs in memory, and remembered per file.
///
/// Keep one for the app. Call `estimate(_:)` as soon as a drag of files starts, again when the
/// ring opens (it reuses the work in progress), and `cancel()` when the drag ends.
@MainActor
public final class Estimator {
    private let cache: SizeCache
    private let conversions: ConversionActivity?
    /// The selection being estimated, until `cancel()` or another selection.
    private var current: (files: [URL], jpegQuality: JPEGQuality, keepingOriginal: Bool, live: LiveOffers)?
    /// Counts selections and cancels, so a selection still being inspected when another one (or
    /// a cancel) comes knows it is out of date.
    private var requests = 0

    private let exactPixelBudget: Int

    /// - Parameters:
    ///   - converter: The converter the app converts with, or a copy of it. Measuring waits while
    ///     it runs a conversion, so it never slows one down.
    ///   - cacheCapacity: How many files' exact sizes are remembered, most recently used first.
    ///   - exactPixelBudget: How many pixels of each selection are measured exactly, one image at
    ///     a time: by default one 48-megapixel photo or four 12-megapixel ones. The other images
    ///     are scaled from the measured ones. This bounds the time and memory measuring takes.
    public init(yieldingTo converter: Converter? = nil, cacheCapacity: Int = 1000,
                exactPixelBudget: Int = 50_000_000) {
        conversions = converter?.activity
        cache = SizeCache(capacity: cacheCapacity)
        self.exactPixelBudget = exactPixelBudget
    }

    /// Starts estimating `files`, and returns once they have been looked at: about a millisecond
    /// for ten files, read off the main actor.
    ///
    /// Images measured before, and unchanged since, are exact from the start; the other estimates
    /// fill in and sharpen as the work goes on. Asking again for the same files while their work
    /// is in progress returns the same `LiveOffers`; once it has finished, a new one checks the
    /// files again (from the cache, so it is quick). Asking for other files cancels the previous
    /// ones, and so does `cancel()`: a `LiveOffers` asked for before either comes back cancelled.
    ///
    /// `keepingOriginal` offers the images Original too, to be saved as they are: for an image
    /// that has no file of its own yet, staged from a drag out of a web page.
    public func estimate(_ files: [URL], jpegQuality: JPEGQuality = .default,
                         keepingOriginal: Bool = false) async -> LiveOffers {
        if let current, current.files == files, current.jpegQuality == jpegQuality,
           current.keepingOriginal == keepingOriginal, !current.live.isCancelled, !current.live.isFinished {
            return current.live
        }
        let previous = current?.live
        cancel()
        let request = requests
        let refinement = await Refinement.start(files, jpegQuality: jpegQuality, keepingOriginal: keepingOriginal,
                                                cache: cache, conversions: conversions,
                                                exactPixelBudget: exactPixelBudget)
        let live = LiveOffers(after: previous, refinement)
        if request == requests {
            current = (files, jpegQuality, keepingOriginal, live)
        } else {
            live.cancel()  // another selection, or a cancel, came meanwhile
        }
        return live
    }

    /// Stops the work for the current selection, as when the drag ends. Sizes measured so far
    /// stay remembered.
    public func cancel() {
        requests += 1
        current?.live.cancel()
        current = nil
    }
}

/// The offers for one selection, with estimates that improve while you watch: quick guesses
/// first, then exact sizes as they are measured.
@MainActor @Observable
public final class LiveOffers {
    /// The latest offers. Targets and skipped files never change; estimates fill in and sharpen.
    public private(set) var offers: Offers
    /// True once the estimates won't change any more: every one is as good as it gets, or the
    /// work was cancelled. Nothing runs in the background from then on.
    public private(set) var isFinished = false

    /// Set by `cancel()`. The offers stop changing at once, though the work may take a moment to
    /// wind down.
    @ObservationIgnored private(set) var isCancelled = false
    /// The quick estimates, which the ring is waiting for.
    @ObservationIgnored private var quickWork: Task<Void, Never>?
    /// Measuring, started by `quickWork` once it is done. Nothing of higher priority awaits it
    /// (that would raise its priority), except `waitUntilFinished()`.
    @ObservationIgnored private var exactWork: Task<Void, Never>?

    /// `previous`, the selection this one replaces, is cancelled. Measuring waits for it to wind
    /// down, so only one image is ever decoded for measuring at a time.
    init(after previous: LiveOffers? = nil, _ refinement: Refinement) {
        offers = refinement.initialOffers()
        quickWork = Task.detached(priority: .userInitiated) { [self] in
            let start = await refinement.quick { offers in await self.publish(offers) }
            await self.measure(from: start, with: refinement, after: previous)
        }
    }

    /// Stops refining. The current encode, if any, can't be interrupted: it finishes (and its
    /// size is remembered), and nothing else starts. `isFinished` turns true once it's done.
    public func cancel() {
        isCancelled = true
        quickWork?.cancel()
        exactWork?.cancel()
    }

    /// Waits until nothing runs in the background any more.
    public func waitUntilFinished() async {
        await quickWork?.value
        await exactWork?.value
    }

    private func measure(from start: Refinement.Start, with refinement: Refinement, after previous: LiveOffers?) {
        guard !isCancelled else { return finish() }
        // Background work: below the quick estimates, the ring and the conversions.
        exactWork = Task.detached(priority: .utility) { [self] in
            await previous?.waitUntilFinished()
            await refinement.exact(from: start) { offers in await self.publish(offers) }
            await self.finish()
        }
    }

    private func publish(_ offers: Offers) {
        guard !isCancelled else { return }
        self.offers = offers
    }

    private func finish() {
        isFinished = true
    }
}
