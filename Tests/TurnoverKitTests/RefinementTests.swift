import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport
import UniformTypeIdentifiers

/// The ring's estimates sharpen in the background: each image output is encoded in memory, and
/// its exact size replaces the quick guess.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct ExactSizes {
    let folder = try! ScratchFolder()

    @Test(arguments: [Fixture.heicRotated, .jpeg, .png, .webp])
    func refiningGivesEveryImageOutputItsExactSize(fixture: Fixture) async throws {
        let image = try folder.add(fixture)

        let live = Estimator().estimate([image])
        await live.waitUntilFinished()

        try await expectExact(live.offers, for: image)
    }

    @Test(arguments: [("photo.heic", UTType.heic), ("photo.jpg", .jpeg)])
    func aCameraSizedPhotoIsRefinedToItsExactSize(name: String, type: UTType) async throws {
        let photo = try folder.addMosaic(of: .heicRotated, width: 2000, height: 1500, as: name, type: type)

        let live = Estimator().estimate([photo])
        await live.waitUntilFinished()

        try await expectExact(live.offers, for: photo)
    }
}

/// Checks that every image target (and every JPEG preset) of `offers` is exact, and matches the
/// size of a real conversion of `image` to within 0.5%.
func expectExact(_ offers: Offers, for image: URL, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    let targets = offers.targets.filter { $0.format != .mp4 }
    #expect(!targets.isEmpty, sourceLocation: sourceLocation)
    for target in targets {
        let presets = target.presets.isEmpty
            ? [(target.format.action(), target.estimate)]
            : target.presets.map { (JPEGAction(quality: $0.quality) as any ConversionAction, Optional($0.estimate)) }
        for (action, estimate) in presets {
            let real = try await outputSize(of: image, with: action)
            #expect(isExact(estimate, of: real), "\(action.name) \(String(describing: estimate)) vs \(real)",
                    sourceLocation: sourceLocation)
        }
    }
}

/// An exact size within 0.5% of `real`.
func isExact(_ estimate: Estimate?, of real: Int) -> Bool {
    guard let estimate, estimate.isExact, let bytes = estimate.bytes else { return false }
    return abs(bytes - real) * 200 <= real
}

/// The ring never waits for the exact sizes: a quick guess comes first, marked approximate.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct QuickThenExact {
    let folder = try! ScratchFolder()

    @Test func aQuickApproximateGuessComesBeforeTheExactSize() async throws {
        let photo = try folder.addMosaic(of: .heicRotated, width: 3000, height: 2000, as: "big.jpg")

        let live = Estimator().estimate([photo])
        let png = Recording { live.offers.targets.first?.estimate }
        await live.waitUntilFinished()

        let estimates = png.values.compactMap { $0 }
        #expect(estimates.first?.isExact == false)
        #expect(estimates.first?.label.hasPrefix("~") == true)
        #expect(estimates.last?.isExact == true)
        #expect(estimates.last?.label.hasPrefix("~") == false)
    }

    @Test func tenPhotosGetTheirFirstEstimatesWithinTheBudget() async throws {
        let fixtures: [Fixture] = [.heicRotated, .jpeg, .png, .webp, .heicRotated, .jpeg, .heicRotated, .webp, .png, .heicRotated]
        let photos = try fixtures.enumerated().map { try folder.add($1, as: "\($0)-\($1.rawValue)") }

        // The fastest of five rounds: the first pays for loading ImageIO, and other tests
        // compete for the CPU.
        var times: [Duration] = []
        for _ in 1...5 {
            let start = ContinuousClock.now
            let live = Estimator().estimate(photos)
            #expect(await eventually { live.offers.targets.allSatisfy { $0.estimate != nil } })
            times.append(ContinuousClock.now - start)
            await live.waitUntilFinished()
        }

        #expect(times.min()! < timeLimit(.milliseconds(50)), "\(times)")
    }
}

/// Exact sizes are remembered per file, so dragging the same photo again shows them at once.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct RememberedSizes {
    let folder = try! ScratchFolder()

    @Test func aSecondRequestForAnUnchangedFileIsExactAtOnce() async throws {
        let photo = try folder.addMosaic(of: .heicRotated, width: 2000, height: 1500, as: "photo.heic", type: .heic)
        let estimator = Estimator()
        await estimator.estimate([photo]).waitUntilFinished()

        let again = estimator.estimate([photo])

        // Before any background work: straight from the cache.
        try await expectExact(again.offers, for: photo)
    }

    @Test func aChangedFileIsMeasuredAgain() async throws {
        let photo = try folder.addMosaic(of: .heicRotated, width: 1200, height: 900, as: "photo.jpg")
        let estimator = Estimator()
        await estimator.estimate([photo]).waitUntilFinished()
        try FileManager.default.removeItem(at: photo)
        try folder.addMosaic(of: .webp, width: 1600, height: 1000, as: "photo.jpg")

        let again = estimator.estimate([photo])

        #expect(again.offers.targets.allSatisfy { $0.estimate == nil })
        await again.waitUntilFinished()
        try await expectExact(again.offers, for: photo)
    }

    @Test func onlyTheMostRecentFilesAreRemembered() async throws {
        let first = try folder.add(.heicRotated, as: "first.heic")
        let second = try folder.add(.webp, as: "second.webp")
        let estimator = Estimator(cacheCapacity: 1)
        await estimator.estimate([first]).waitUntilFinished()
        await estimator.estimate([second]).waitUntilFinished()

        #expect(estimator.estimate([second]).offers.targets.allSatisfy { $0.estimate?.isExact == true })
        #expect(estimator.estimate([first]).offers.targets.allSatisfy { $0.estimate == nil })
    }
}

/// Refining starts when a drag starts and stops when it ends or the selection changes.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct StoppingRefinement {
    let folder = try! ScratchFolder()

    /// Three 6-megapixel photos: a few hundred milliseconds of encoding each.
    func photos() throws -> [URL] {
        let first = try folder.addMosaic(of: .heicRotated, width: 3000, height: 2000, as: "1.jpg")
        return try [first] + (2...3).map { index in
            let copy = folder.url.appendingPathComponent("\(index).jpg")
            try FileManager.default.copyItem(at: first, to: copy)
            return copy
        }
    }

    @Test func cancellingStopsTheWorkAndLeavesNothingRunning() async throws {
        let photos = try photos()
        let estimator = Estimator()
        let live = estimator.estimate(photos)
        #expect(await eventually { live.offers.targets.first?.estimate != nil })

        let cancelled = ContinuousClock.now
        live.cancel()
        await live.waitUntilFinished()

        #expect(ContinuousClock.now - cancelled < timeLimit(.seconds(1)))
        #expect(live.isFinished)
        let last = live.offers
        try await Task.sleep(for: .milliseconds(300))
        #expect(live.offers == last)
        // Nothing was measured after the cancel: the last photo was never encoded.
        let again = estimator.estimate([photos[2]])
        #expect(again.offers.targets.allSatisfy { $0.estimate == nil })
        again.cancel()
    }

    @Test func theEstimatorCancelsWhenTheDragEnds() async throws {
        let estimator = Estimator()
        let live = estimator.estimate(try photos())

        estimator.cancel()
        await live.waitUntilFinished()

        #expect(live.isFinished)
        #expect(live.offers.targets.contains { $0.estimate?.isExact != true })
    }

    @Test func askingAgainForTheSameFilesReusesTheWorkInProgress() async throws {
        let photos = try photos()
        let estimator = Estimator()

        let atDragStart = estimator.estimate(photos)
        let onTheRing = estimator.estimate(photos)

        #expect(onTheRing === atDragStart)
        estimator.cancel()
    }

    @Test func aNewSelectionCancelsThePreviousOne() async throws {
        let photos = try photos()
        let estimator = Estimator()
        let first = estimator.estimate(photos)

        let second = estimator.estimate([photos[0]])
        await first.waitUntilFinished()

        #expect(second !== first)
        #expect(first.offers.targets.contains { $0.estimate?.isExact != true })
        await second.waitUntilFinished()
        try await expectExact(second.offers, for: photos[0])
    }
}

/// Big selections stay cheap: a few photos are measured exactly and the rest are scaled from them.
@MainActor
@Suite(.timeLimit(.minutes(2))) struct BoundedRefinement {
    let folder = try! ScratchFolder()

    @Test func aLargeSelectionRefinesAFewPhotosAndScalesTheRestFromThem() async throws {
        // Eight copies of one 12-megapixel photo: scaling from any of them is right for all.
        let first = try folder.addMosaic(of: .heicRotated, width: 4000, height: 3000, as: "1.jpg")
        let photos = try [first] + (2...8).map { index in
            let copy = folder.url.appendingPathComponent("\(index).jpg")
            try FileManager.default.copyItem(at: first, to: copy)
            return copy
        }
        let real = try await outputSize(of: first, with: PNGAction())
        let estimator = Estimator()

        let live = estimator.estimate(photos)
        await live.waitUntilFinished()

        let png = try #require(live.offers.targets.first?.estimate)
        #expect(!png.isExact)
        #expect(abs(try bytes(png) - real * 8) * 100 <= real * 8, "within 1%")
        // Only a few were encoded; the others are remembered as unmeasured.
        let measured = photos.filter { estimator.estimate([$0]).offers.targets.first?.estimate?.isExact == true }
        estimator.cancel()
        #expect((1...4).contains(measured.count), "\(measured.count) measured")
    }
}
