import Foundation
import Observation

/// Works out offers for live UI (the ring): quick estimates first, then exact image sizes,
/// measured in the background by encoding the real outputs in memory.
///
/// Keep one for the app.
@MainActor
public final class Estimator {
    private let cache: SizeCache

    /// `cacheCapacity` is how many files' exact sizes are remembered, most recently used first.
    public init(cacheCapacity: Int = 1000) {
        cache = SizeCache(capacity: cacheCapacity)
    }

    /// Starts estimating `files` and returns at once. Images measured before, and unchanged since,
    /// are exact from the start; the other estimates fill in and sharpen as the work goes on.
    public func estimate(_ files: [URL], jpegQuality: JPEGQuality = .default) -> LiveOffers {
        LiveOffers(Refinement(files: files, inspection: Offers.Inspection(files), jpegQuality: jpegQuality, cache: cache))
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

    init(_ refinement: Refinement) {
        offers = refinement.initialOffers()
        work = Task.detached(priority: .utility) { [self] in
            await refinement.run { offers in await self.publish(offers) }
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
