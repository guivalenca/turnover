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
