import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// The approximate output size each image target shows, checked against real conversions.
@Suite struct ImageSizeEstimates {
    let folder = try! ScratchFolder()

    @Test(arguments: [Fixture.heicRotated, .jpeg, .png, .webp])
    func eachImageTargetEstimatesItsSizeWithinAFactorOfTwo(fixture: Fixture) async throws {
        let image = try folder.add(fixture)

        let offers = await Offers(estimating: [image])

        #expect(!offers.targets.isEmpty)
        for target in offers.targets {
            let real = try await outputSize(of: image, with: target.format.action())
            #expect(try isWithinFactorOfTwo(target.estimate, of: real), "\(target.format)")
        }
    }

    @Test(arguments: [Fixture.heicRotated, .png, .webp])
    func jpegEstimatesEachPresetAndShowsTheChosenOne(fixture: Fixture) async throws {
        let image = try folder.add(fixture)

        let offers = await Offers(estimating: [image], jpegQuality: .small)

        let jpeg = try #require(offers.targets.first { $0.format == .jpeg })
        #expect(jpeg.quality == .small)
        #expect(jpeg.presets.map(\.quality) == [.best, .high, .small])
        for preset in jpeg.presets {
            let real = try await outputSize(of: image, with: JPEGAction(quality: preset.quality))
            #expect(try isWithinFactorOfTwo(preset.estimate, of: real), "\(preset.quality)")
        }
        #expect(jpeg.estimate == jpeg.presets.last?.estimate)
        // Each step down in quality saves space.
        let sizes = try jpeg.presets.map { try bytes($0.estimate) }
        #expect(sizes == sizes.sorted(by: >))
    }

    @Test func onlyJPEGHasPresets() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let movie = try folder.add(.movH264, as: "clip.mov")

        let offers = await Offers(estimating: [photo, movie])

        #expect(offers.targets.map(\.presets.isEmpty) == [true, false, true])
        #expect(offers.targets.map(\.quality) == [nil, .high, nil])
    }

    @Test func aTargetForSeveralImagesEstimatesTheirTotal() async throws {
        let first = try folder.add(.heicRotated, as: "one.heic")
        let second = try folder.add(.webp, as: "two.webp")

        let offers = await Offers(estimating: [first, second])

        let png = try #require(offers.targets.first)
        let real = try await outputSize(of: first, with: PNGAction()) + outputSize(of: second, with: PNGAction())
        #expect(try isWithinFactorOfTwo(png.estimate, of: real))
    }

    /// Converts a copy of `image` in a folder of its own and returns the output's size in bytes.
    private func outputSize(of image: URL, with action: some ConversionAction) async throws -> Int {
        let scratch = try ScratchFolder()
        let copy = scratch.url.appendingPathComponent(image.lastPathComponent)
        try FileManager.default.copyItem(at: image, to: copy)
        let output = try await Converter().convert(copy, with: action).output
        return try output.resourceValues(forKeys: [.fileSizeKey]).fileSize!
    }
}

/// How long MP4 says it will take.
@Suite struct VideoTimeEstimates {
    let folder = try! ScratchFolder()

    @Test(arguments: [Fixture.movH264, .movH264PCM, .movH264Silent])
    func h264IsInstant(fixture: Fixture) async throws {
        let movie = try folder.add(fixture, as: "clip.mov")

        let offers = await Offers(estimating: [movie])

        #expect(offers.targets.map(\.estimate) == [.instant])
        #expect(offers.targets.first?.estimate?.label == "Instant")
    }

    @Test func anythingElseTakesAnApproximateTime() async throws {
        let movie = try folder.add(.movHEVCHDR, as: "clip.mov")

        let offers = await Offers(estimating: [movie])

        let estimate = try #require(offers.targets.first?.estimate)
        guard case .duration(let seconds) = estimate else { Issue.record("\(estimate)"); return }
        #expect(seconds > 0 && seconds < 1)
        #expect(estimate.label == "About 1 s")
    }

    @Test func oneTranscodeAmongCopiesMakesTheBatchTimed() async throws {
        let copied = try folder.add(.movH264, as: "copied.mov")
        let encoded = try folder.add(.movHEVCHDR, as: "encoded.mov")

        let offers = await Offers(estimating: [copied, encoded])

        #expect(offers.targets.first?.files == [copied, encoded])
        #expect(offers.targets.first?.estimate?.label == "About 1 s")
    }

    @Test func aDamagedVideoIsStillOfferedButNotEstimated() async throws {
        let whole = try folder.add(.movH264, as: "whole.mov")
        let broken = try folder.add(Fixture.movHEVCHDR.data.prefix(20_000), as: "broken.mov")

        let offers = await Offers(estimating: [whole, broken])
        let onlyBroken = await Offers(estimating: [broken])

        #expect(offers.targets.first?.files == [whole, broken])
        #expect(offers.targets.first?.estimate == .instant)
        #expect(onlyBroken.targets.map(\.files) == [[broken]])
        #expect(onlyBroken.targets.first?.estimate == nil)
    }
}

/// How estimates read on screen: every one is marked approximate.
@Suite struct EstimateLabels {
    @Test(arguments: [
        (400, "~1 KB"),
        (31_000, "~31 KB"),
        (999_400, "~999 KB"),
        (999_600, "~1.0 MB"),
        (1_240_000, "~1.2 MB"),
        (9_960_000, "~10 MB"),
        (19_400_000, "~19 MB"),
        (2_345_000_000, "~2.3 GB"),
    ])
    func sizesUseFinderUnitsAndATilde(bytes: Int, label: String) {
        #expect(Estimate.size(bytes).label == label)
    }

    @Test(arguments: [
        (0.2, "About 1 s"),
        (4.1, "About 5 s"),
        (59, "About 59 s"),
        (60, "About 1 min"),
        (149, "About 2 min"),
        (3_000, "About 50 min"),
    ])
    func durationsSayAbout(seconds: Double, label: String) {
        #expect(Estimate.duration(seconds).label == label)
    }
}

func bytes(_ estimate: Estimate?) throws -> Int {
    guard case .size(let bytes) = estimate else { throw EstimateMismatch(estimate: estimate) }
    return bytes
}

func isWithinFactorOfTwo(_ estimate: Estimate?, of real: Int) throws -> Bool {
    let estimated = try bytes(estimate)
    return estimated <= real * 2 && estimated * 2 >= real
}

struct EstimateMismatch: Error {
    let estimate: Estimate?
}
