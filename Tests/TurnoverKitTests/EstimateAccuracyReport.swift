import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// How close the quick estimate comes on real photos, which can't be committed: run it on your own
/// with a file listing image paths, one per line.
///
///     TURNOVER_ACCURACY_PHOTOS=~/photos.txt swift test --filter QuickEstimateAccuracy
///
/// Prints each photo's ratios (estimate ÷ real output, for the outputs its format is offered),
/// the range per output, and the quick estimate's time per photo. Converts copies in a temporary
/// folder; never writes next to the photos.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TURNOVER_ACCURACY_PHOTOS"] != nil),
       .timeLimit(.minutes(30)))
struct QuickEstimateAccuracy {
    @Test func theQuickEstimateIsWithinAFactorOf1Point5() async throws {
        let list = try String(contentsOfFile: ProcessInfo.processInfo.environment["TURNOVER_ACCURACY_PHOTOS"]!,
                              encoding: .utf8)
        let photos = list.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
        var lines: [String] = []
        var ranges: [String: ClosedRange<Double>] = [:]
        var times: [Duration] = []
        for photo in photos {
            var offers: Offers?
            // The fastest of three, as in the speed tests.
            let time = await (1...3).asyncMin { _ in await ContinuousClock().measure { offers = await Offers(estimating: [photo]) } }
            times.append(time)
            var ratios: [String] = []
            for target in offers?.targets ?? [] {
                let estimates = target.presets.isEmpty
                    ? [(target.format.name, target.format.action(), target.estimate)]
                    : target.presets.map { ("\(target.format.name) \($0.quality.name)", target.format.action(quality: $0.quality), Optional($0.estimate)) }
                for (name, action, estimate) in estimates {
                    let real = try await outputSize(of: photo, with: action)
                    let ratio = Double(try bytes(estimate)) / Double(real)
                    ranges[name] = min(ratio, ranges[name]?.lowerBound ?? ratio)...max(ratio, ranges[name]?.upperBound ?? ratio)
                    ratios.append(String(format: "%@ %.2f", name, ratio))
                }
            }
            lines.append("\(photo.lastPathComponent)  \(time)  \(ratios.joined(separator: ", "))")
        }
        let all = ranges.values.reduce(ranges.values.first!) { min($0.lowerBound, $1.lowerBound)...max($0.upperBound, $1.upperBound) }
        let sorted = times.sorted()
        print(lines.joined(separator: "\n"))
        print(ranges.sorted { $0.key < $1.key }.map { String(format: "%@ %.2f–%.2f", $0.key, $0.value.lowerBound, $0.value.upperBound) }
            .joined(separator: ", "))
        print(String(format: "all %.2f–%.2f over %d photos; quick estimate median %@, slowest %@",
                     all.lowerBound, all.upperBound, photos.count, "\(sorted[sorted.count / 2])", "\(sorted.last!)"))
        #expect(all.lowerBound >= 1 / 1.5 && all.upperBound <= 1.5)
    }
}

/// How long the ring waits for an exact size, on the listed photos of 10 to 14 megapixels
/// (`TURNOVER_ACCURACY_PHOTOS` as above). Each is measured from scratch, fastest of three.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TURNOVER_ACCURACY_PHOTOS"] != nil),
       .timeLimit(.minutes(30)))
struct TimeToExactReport {
    @Test func timeToAnExactSizeFor12MegapixelPhotos() async throws {
        let list = try String(contentsOfFile: ProcessInfo.processInfo.environment["TURNOVER_ACCURACY_PHOTOS"]!,
                              encoding: .utf8)
        let photos = list.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }.filter { photo in
            guard let facts = try? ImageFacts(photo) else { return false }
            return (10_000_000...14_000_000).contains(facts.width * facts.height)
        }
        for photo in photos {
            var png: [Duration] = [], jpeg: [Duration] = []
            for _ in 1...3 {
                let (toPNG, toJPEG) = await timeToExact(photo)
                png.append(toPNG)
                jpeg.append(toJPEG)
            }
            print("\(photo.lastPathComponent): PNG exact after \(png.min()!), JPEG after \(jpeg.min()!) (first run \(png[0]), \(jpeg[0]))")
        }
        #expect(!photos.isEmpty)
    }
}

extension ClosedRange<Int> {
    /// The smallest of `transform` over the range, run one after another.
    func asyncMin(_ transform: (Int) async -> Duration) async -> Duration {
        var best = Duration.seconds(Int64.max)
        for value in self { best = Swift.min(best, await transform(value)) }
        return best
    }
}
