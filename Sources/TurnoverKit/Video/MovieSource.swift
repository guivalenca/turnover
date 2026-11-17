@preconcurrency import AVFoundation
import Foundation

/// The parts of a movie that go into the MP4, and what the conversion needs to know about them:
/// the first enabled video track and the first enabled audio track, if any.
struct MovieSource {
    struct Video {
        let track: AVAssetTrack
        let format: CMFormatDescription
        /// The display matrix, which turns portrait recordings upright.
        let transform: CGAffineTransform
        let frameRate: Double
        /// Bits per second.
        let dataRate: Double

        /// Whether the video can be copied into the MP4 untouched.
        var isWidelyPlayable: Bool { H264.isWidelyPlayable(format) }
    }

    struct Audio {
        let track: AVAssetTrack
        let format: CMFormatDescription
    }

    let asset: AVURLAsset
    let duration: CMTime
    let video: Video
    let audio: Audio?

    /// Reads the movie's tracks. Throws `ConversionError.damaged` when the file can't be parsed
    /// and `.notApplicable` when it has no video.
    init(_ url: URL) async throws {
        asset = AVURLAsset(url: url)
        do {
            duration = try await asset.load(.duration)
            guard let track = try await Self.firstEnabledTrack(of: .video, in: asset),
                  let format = try await track.load(.formatDescriptions).first
            else { throw ConversionError.notApplicable(url, format: "MP4") }
            let (transform, frameRate, dataRate) = try await track.load(.preferredTransform, .nominalFrameRate, .estimatedDataRate)
            video = Video(track: track, format: format, transform: transform, frameRate: Double(frameRate), dataRate: Double(dataRate))

            if let track = try await Self.firstEnabledTrack(of: .audio, in: asset),
               let format = try await track.load(.formatDescriptions).first {
                audio = Audio(track: track, format: format)
            } else {
                audio = nil
            }
        } catch let error as ConversionError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ConversionError.damaged(url)
        }
    }

    private static func firstEnabledTrack(of type: AVMediaType, in asset: AVAsset) async throws -> AVAssetTrack? {
        for track in try await asset.loadTracks(withMediaType: type) where try await track.load(.isEnabled) {
            return track
        }
        return nil
    }
}
