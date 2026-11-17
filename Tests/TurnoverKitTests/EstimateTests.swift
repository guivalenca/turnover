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
