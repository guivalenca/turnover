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

        let live = await Estimator().estimate([image])
        await live.waitUntilFinished()

        try await expectExact(live.offers, for: image)
    }

    @Test(arguments: [("photo.heic", UTType.heic), ("photo.jpg", .jpeg)])
    func aCameraSizedPhotoIsRefinedToItsExactSize(name: String, type: UTType) async throws {
        let photo = try await mosaic(in: folder, of: .heicRotated, width: 2000, height: 1500, as: name, type: type)

        let live = await Estimator().estimate([photo])
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
            : target.presets.map { (OutputFormat.jpeg.action(quality: $0.quality), Optional($0.estimate)) }
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
        let photo = try await mosaic(in: folder, of: .heicRotated, width: 3000, height: 2000, as: "big.jpg")

        let live = await Estimator().estimate([photo])
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
            let live = await Estimator().estimate(photos)
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
        let photo = try await mosaic(in: folder, of: .heicRotated, width: 2000, height: 1500, as: "photo.heic", type: .heic)
        let estimator = Estimator()
        await estimator.estimate([photo]).waitUntilFinished()

        let again = await estimator.estimate([photo])

        // Before any background work: straight from the cache.
        try await expectExact(again.offers, for: photo)
    }

    @Test func aChangedFileIsMeasuredAgain() async throws {
        let photo = try await mosaic(in: folder, of: .heicRotated, width: 1200, height: 900, as: "photo.jpg")
        let estimator = Estimator()
        await estimator.estimate([photo]).waitUntilFinished()
        try FileManager.default.removeItem(at: photo)
        try await mosaic(in: folder, of: .webp, width: 1600, height: 1000, as: "photo.jpg")

        let again = await estimator.estimate([photo])

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

        #expect(await estimator.estimate([second]).offers.targets.allSatisfy { $0.estimate?.isExact == true })
        #expect(await estimator.estimate([first]).offers.targets.allSatisfy { $0.estimate == nil })
    }
}

/// Refining starts when a drag starts and stops when it ends or the selection changes.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct StoppingRefinement {
    let folder = try! ScratchFolder()

    /// Three 6-megapixel photos: a few hundred milliseconds of encoding each.
    func photos() async throws -> [URL] {
        let first = try await mosaic(in: folder, of: .heicRotated, width: 3000, height: 2000, as: "1.jpg")
        return try [first] + (2...3).map { index in
            let copy = folder.url.appendingPathComponent("\(index).jpg")
            try FileManager.default.copyItem(at: first, to: copy)
            return copy
        }
    }

    /// Each photo has one output, PNG. The encode under way when the drag ends can't be stopped,
    /// so one more photo may become measured; nothing else may. (How long that encode takes to
    /// finish, at utility priority, depends on what else the machine is doing, so it isn't timed.)
    @Test func cancellingStopsTheWorkAndLeavesNothingRunning() async throws {
        let photos = try await photos()
        let estimator = Estimator()
        let live = await estimator.estimate(photos)
        #expect(await eventually { live.offers.targets.first?.estimate != nil })

        live.cancel()
        let measuredAtCancel = await remembered(photos, by: estimator)
        await live.waitUntilFinished()

        #expect(live.isFinished)
        let offers = live.offers
        let measured = await remembered(photos, by: estimator)
        #expect(measured.count <= measuredAtCancel.count + 1, "\(measuredAtCancel.count) measured at the cancel, \(measured.count) once stopped")
        try await Task.sleep(for: .milliseconds(300))
        // Nothing changes any more: neither the offers nor what is remembered.
        #expect(live.offers == offers)
        #expect(await remembered(photos, by: estimator) == measured)
    }

    @Test func theEstimatorCancelsWhenTheDragEnds() async throws {
        let photos = try await photos()
        let estimator = Estimator()
        let live = await estimator.estimate(photos)

        estimator.cancel()
        await live.waitUntilFinished()

        #expect(live.isFinished)
        #expect(live.offers.targets.allSatisfy { $0.estimate?.isExact != true })
        // Cancelled before the quick estimates were in: nothing was measured.
        #expect(await remembered(photos, by: estimator) == [])
    }

    @Test func askingAgainForTheSameFilesReusesTheWorkInProgress() async throws {
        let photos = try await photos()
        let estimator = Estimator()

        let atDragStart = await estimator.estimate(photos)
        let onTheRing = await estimator.estimate(photos)

        #expect(onTheRing === atDragStart)
        estimator.cancel()
    }

    @Test func aNewSelectionCancelsThePreviousOne() async throws {
        let photos = try await photos()
        let estimator = Estimator()
        let first = await estimator.estimate(photos)

        let second = await estimator.estimate([photos[0]])
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
        // Eight copies of one 1-megapixel photo, and a budget of 3 megapixels: two or so are
        // measured, and scaling from them is right for all.
        let first = try await mosaic(in: folder, of: .heicRotated, width: 1200, height: 900, as: "1.jpg")
        let photos = try [first] + (2...8).map { index in
            let copy = folder.url.appendingPathComponent("\(index).jpg")
            try FileManager.default.copyItem(at: first, to: copy)
            return copy
        }
        let real = try await outputSize(of: first, with: PNGAction())
        let estimator = Estimator(exactPixelBudget: 3_000_000)

        let live = await estimator.estimate(photos)
        await live.waitUntilFinished()

        let png = try #require(live.offers.targets.first?.estimate)
        #expect(!png.isExact)
        #expect(abs(try bytes(png) - real * 8) * 100 <= real * 8, "within 1%")
        // Only a few were encoded; the others are remembered as unmeasured.
        var measured: [URL] = []
        for photo in photos where await estimator.estimate([photo]).offers.targets.first?.estimate?.isExact == true {
            measured.append(photo)
        }
        estimator.cancel()
        #expect(measured.count == 2, "\(measured.count) measured")
    }
}

/// A total is exact only when every file in it is.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct HonestTotals {
    let folder = try! ScratchFolder()

    @Test func aTotalIsNeverExactBeforeEveryOutputOfEveryPhotoIsMeasured() async throws {
        // More photos than the quick estimate samples, so the last one starts with no estimate of
        // its own; each has four outputs, measured one at a time.
        let first = try await mosaic(in: folder, of: .heicRotated, width: 1200, height: 900, as: "1.heic", type: .heic)
        let photos = try [first] + (2...ImageSizesSampled.count + 1).map { index in
            let copy = folder.url.appendingPathComponent("\(index).heic")
            try FileManager.default.copyItem(at: first, to: copy)
            return copy
        }

        let live = await Estimator().estimate(photos)
        let png = Recording { live.offers.targets.first { $0.format == .png }?.estimate }
        let small = Recording { live.offers.targets.first { $0.format == .jpeg }?.presets.last?.estimate }
        await live.waitUntilFinished()

        for estimates in [png.values, small.values] {
            let exact = estimates.compactMap { $0 }.filter(\.isExact)
            #expect(!exact.isEmpty)
            #expect(Set(exact).count == 1, "\(exact)")
        }
    }

    /// A HEIC cut short decodes to whatever ImageIO makes of the missing data: it has no size.
    @Test func aHEICCutShortIsNeverMeasured() async throws {
        let broken = try folder.add(Fixture.heicRotated.data.prefix(4_500), as: "broken.heic")

        let live = await Estimator().estimate([broken])
        await live.waitUntilFinished()

        #expect(live.offers.targets.map(\.format) == [.png, .jpeg])
        #expect(live.offers.targets.map(\.estimate) == [nil, nil])
    }

    @Test func aFileThatCantBeMeasuredMakesTheTotalApproximate() async throws {
        let whole = try folder.add(.png, as: "logo.png")
        // Cut in its header: offered as an image, but it can't be decoded.
        let broken = try folder.add(Fixture.heicRotated.data.prefix(1_000), as: "broken.heic")

        let live = await Estimator().estimate([whole, broken])
        await live.waitUntilFinished()

        let jpeg = try #require(live.offers.targets.first { $0.format == .jpeg })
        #expect(jpeg.files == [whole, broken])
        #expect(jpeg.estimate?.isExact == false, "\(String(describing: jpeg.estimate))")
    }
}

/// How many photos the quick estimate samples (`ImageSizes.sampledImages`, which is internal).
enum ImageSizesSampled {
    static let count = 4
}

/// Refining is background work: it never competes with a conversion the user asked for.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct YieldingToConversions {
    let folder = try! ScratchFolder()

    @Test func refiningWaitsWhileAConversionRunsThenCarriesOn() async throws {
        let converter = Converter()
        let turnstile = Turnstile()
        let busy = try folder.add(.heicRotated, as: "busy.heic")
        let photo = try await mosaic(in: folder, of: .heicRotated, width: 2000, height: 1500, as: "photo.jpg")
        let conversion = Task { try await converter.convert(busy, with: turnstile.holding(PNGAction())) }
        #expect(await turnstile.waitUntil(running: 1))

        let live = await Estimator(yieldingTo: converter).estimate([photo])

        // The quick guess still comes at once; the exact size waits for the conversion.
        #expect(await eventually { live.offers.targets.first?.estimate != nil })
        try await Task.sleep(for: .milliseconds(500))
        #expect(live.offers.targets.first?.estimate?.isExact == false)
        turnstile.open()
        _ = try await conversion.value
        await live.waitUntilFinished()
        try await expectExact(live.offers, for: photo)
    }

    @Test func cancellingWhileWaitingForAConversionStopsAtOnce() async throws {
        let converter = Converter()
        let turnstile = Turnstile()
        let busy = try folder.add(.heicRotated, as: "busy.heic")
        let photo = try await mosaic(in: folder, of: .heicRotated, width: 2000, height: 1500, as: "photo.jpg")
        let conversion = Task { try await converter.convert(busy, with: turnstile.holding(PNGAction())) }
        #expect(await turnstile.waitUntil(running: 1))
        let estimator = Estimator(yieldingTo: converter)
        let live = await estimator.estimate([photo])
        #expect(await eventually { live.offers.targets.first?.estimate != nil })

        let cancelled = ContinuousClock.now
        live.cancel()
        await live.waitUntilFinished()

        #expect(ContinuousClock.now - cancelled < timeLimit(.milliseconds(200)))
        turnstile.open()
        _ = try await conversion.value
        try await Task.sleep(for: .milliseconds(300))
        #expect(await remembered([photo], by: estimator) == [])
    }
}

/// How soon the ring shows exact sizes for a typical photo.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct TimeToExact {
    let folder = try! ScratchFolder()

    /// CI's virtual machines decode HEIC in software and share three cores among every test (it
    /// took 21 s there), so this runs on Macs only; see the #17 notes for measured times.
    @Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "software HEVC on CI's virtual machines"))
    func a12MegapixelPhotoIsExactWithinASecond() async throws {
        let photo = try await mosaic(in: folder, of: .heicRotated, width: 4032, height: 3024, as: "photo.heic", type: .heic)

        // The fastest of three, each from scratch: the first pays for loading the HEVC decoder,
        // and other tests compete for the CPU.
        var png: [Duration] = [], jpeg: [Duration] = []
        for _ in 1...3 {
            let (toPNG, toJPEG) = await timeToExact(photo)
            png.append(toPNG)
            jpeg.append(toJPEG)
        }

        #expect(png.min()! < timeLimit(.seconds(1)), "\(png)")
        #expect(jpeg.min()! < timeLimit(.seconds(1)), "\(jpeg)")
    }

    /// A JPEG takes a few milliseconds to encode and a PNG hundreds, so the JPEG the ring shows
    /// is measured first, then the other presets, then PNG.
    @Test func theDefaultJPEGIsExactBeforeThePNG() async throws {
        let photo = try await mosaic(in: folder, of: .heicRotated, width: 2000, height: 1500, as: "photo.heic", type: .heic)

        let live = await Estimator().estimate([photo], jpegQuality: .small)
        let exact = Recording { live.offers.targets.filter { $0.estimate?.isExact == true }.map(\.format) }
        let presets = Recording { live.offers.targets.last?.presets.filter(\.estimate.isExact).map(\.quality) ?? [] }
        await live.waitUntilFinished()

        #expect(exact.values.last == [.png, .jpeg])
        #expect(exact.values.contains([.jpeg]))
        #expect(presets.values.first { !$0.isEmpty } == [.jpeg(.small)])
    }
}

/// How long a fresh `Estimator` takes to show `photo`'s PNG size, then its default JPEG size,
/// exactly. `.zero` for a format the photo isn't offered.
@MainActor
func timeToExact(_ photo: URL) async -> (png: Duration, jpeg: Duration) {
    let start = ContinuousClock.now
    let live = await Estimator().estimate([photo])
    var times: [OutputFormat: Duration] = [:]
    let formats = live.offers.targets.map(\.format).filter { $0 != .mp4 }
    _ = await eventually(timeout: .seconds(30)) {
        for target in live.offers.targets where times[target.format] == nil && target.estimate?.isExact == true {
            times[target.format] = ContinuousClock.now - start
        }
        return formats.allSatisfy { times[$0] != nil }
    }
    live.cancel()
    await live.waitUntilFinished()
    return (times[.png] ?? .zero, times[.jpeg] ?? .zero)
}

/// `folder.addMosaic(…)`, made on a dispatch queue: a camera-sized photo takes a while to make
/// (on CI, seconds), and the other tests need the main actor and the concurrency threads meanwhile.
@discardableResult
func mosaic(in folder: ScratchFolder, of fixture: Fixture, width: Int, height: Int, as name: String,
            type: UTType = .jpeg) async throws -> URL {
    try await offThePool { try folder.addMosaic(of: fixture, width: width, height: height, as: name, type: type) }
}

/// The files of `files` whose sizes `estimator` remembers exactly. Asking cancels the selection in
/// progress, so call it once that is finished.
@MainActor
func remembered(_ files: [URL], by estimator: Estimator) async -> [URL] {
    var known: [URL] = []
    for file in files {
        let offers = await estimator.estimate([file]).offers
        if !offers.targets.isEmpty, offers.targets.allSatisfy({ $0.estimate?.isExact == true }) { known.append(file) }
    }
    estimator.cancel()
    return known
}
