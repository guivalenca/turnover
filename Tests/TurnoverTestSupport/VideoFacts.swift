import AVFoundation
import CoreMedia
import CryptoKit
import Foundation

/// What AVFoundation sees in a movie file, read independently of TurnoverKit so tests can check
/// outputs. Video facts describe the first video track; audio facts the first audio track.
public struct VideoFacts: Sendable {
    /// The `ftyp` major brand, e.g. "qt  " for QuickTime or "mp42" for MPEG-4.
    public let majorBrand: String
    /// The video codec's four-character code, e.g. "avc1" (H.264) or "hvc1" (HEVC).
    public let videoCodec: String
    /// The audio codec's four-character code, e.g. "aac ", or nil when there is no audio track.
    public let audioCodec: String?
    /// The stored frame size, before the track's display matrix.
    public let width: Int
    public let height: Int
    /// The size a player shows: the stored size turned by the track's display matrix.
    public let displayWidth: Int
    public let displayHeight: Int
    public let frameRate: Double
    public let duration: Double
    /// The colour tags on the video format, e.g. "ITU_R_709_2"; nil when untagged.
    public let colorPrimaries: String?
    public let transferFunction: String?
    public let yCbCrMatrix: String?
    /// The H.264 profile (`profile_idc` from avcC): 66 Baseline, 77 Main, 100 High (all 8-bit
    /// 4:2:0), 110 High 10, …. Nil for other codecs.
    public let h264Profile: Int?
    private let url: URL

    public init(_ url: URL) async throws {
        self.url = url
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first,
              let format = try await video.load(.formatDescriptions).first
        else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url]) }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let (size, transform, frameRate) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let display = size.applying(transform)

        majorBrand = Self.majorBrand(url)
        videoCodec = Self.fourCC(CMFormatDescriptionGetMediaSubType(format))
        audioCodec = try await audio?.load(.formatDescriptions).first.map { Self.fourCC(CMFormatDescriptionGetMediaSubType($0)) }
        (width, height) = (Int(size.width.rounded()), Int(size.height.rounded()))
        (displayWidth, displayHeight) = (Int(abs(display.width).rounded()), Int(abs(display.height).rounded()))
        self.frameRate = Double(frameRate)
        duration = try await asset.load(.duration).seconds
        let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        colorPrimaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String
        transferFunction = extensions[kCVImageBufferTransferFunctionKey as String] as? String
        yCbCrMatrix = extensions[kCVImageBufferYCbCrMatrixKey as String] as? String
        let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any]
        h264Profile = (atoms?["avcC"] as? Data).flatMap { $0.count > 1 ? Int($0[$0.startIndex + 1]) : nil }
    }

    /// A digest of every compressed video sample, in order: equal digests mean the video
    /// stream was copied bit for bit, not re-encoded.
    public func videoSamplesDigest() async throws -> String {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var hash = SHA256()
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var bytes = Data(count: CMBlockBufferGetDataLength(block))
            _ = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!) }
            hash.update(data: bytes)
        }
        if let error = reader.error { throw error }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func majorBrand(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let header = try? handle.read(upToCount: 12), header.count == 12
        else { return "" }
        try? handle.close()
        return String(decoding: header[header.startIndex + 8 ..< header.startIndex + 12], as: UTF8.self)
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        String(decoding: withUnsafeBytes(of: code.bigEndian) { Array($0) }, as: UTF8.self)
    }
}
