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
    /// The selection being estimated, until `cancel()` or another selection.
    private var current: (files: [URL], jpegQuality: JPEGQuality, live: LiveOffers)?

    /// `cacheCapacity` is how many files' exact sizes are remembered, most recently used first.
    public init(cacheCapacity: Int = 1000) {
        cache = SizeCache(capacity: cacheCapacity)
    }

    /// Starts estimating `files` and returns at once.
    ///
    /// Images measured before, and unchanged since, are exact from the start; the other estimates
    /// fill in and sharpen as the work goes on. Asking again for the same files returns the same
    /// `LiveOffers`, work and all; asking for other files cancels the previous ones.
    public func estimate(_ files: [URL], jpegQuality: JPEGQuality = .default) -> LiveOffers {
        if let current, current.files == files, current.jpegQuality == jpegQuality, !current.live.isCancelled {
            return current.live
        }
        current?.live.cancel()
        let live = LiveOffers(Refinement(files: files, inspection: Offers.Inspection(files),
                                         jpegQuality: jpegQuality, cache: cache))
        current = (files, jpegQuality, live)
        return live
    }

    /// Stops the work for the current selection, as when the drag ends. Sizes measured so far
    /// stay remembered.
    public func cancel() {
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
    @ObservationIgnored private var work: Task<Void, Never>?

    init(_ refinement: Refinement) {
        offers = refinement.initialOffers()
        work = Task.detached(priority: .utility) { [self] in
            await refinement.run { offers in await self.publish(offers) }
            await self.finish()
        }
    }

    /// Stops refining. The current encode, if any, can't be interrupted: it finishes (and its
    /// size is remembered), and nothing else starts. `isFinished` turns true once it's done.
    public func cancel() {
        isCancelled = true
        work?.cancel()
    }

    /// Waits until nothing runs in the background any more.
    public func waitUntilFinished() async {
        await work?.value
    }

    private func publish(_ offers: Offers) {
        guard !isCancelled else { return }
        self.offers = offers
    }

    private func finish() {
        isFinished = true
    }
}
