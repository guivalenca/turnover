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
