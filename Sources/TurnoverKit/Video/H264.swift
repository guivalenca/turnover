import AVFoundation
import CoreMedia

/// What "plays everywhere" means for video: 8-bit 4:2:0 H.264, tagged BT.709.
enum H264 {
    /// Whether a video stream can go into the MP4 untouched: H.264 in one of the 8-bit 4:2:0
    /// profiles (Baseline, Main, High). High 10, 4:2:2 and 4:4:4 H.264 are re-encoded, since
    /// many players can't decode them.
    static func isWidelyPlayable(_ format: CMFormatDescription) -> Bool {
        guard format.mediaSubType == .h264 else { return false }
        let atoms = format.extensions[.sampleDescriptionExtensionAtoms]?.propertyListRepresentation as? [String: Any]
        guard let avcC = atoms?["avcC"] as? Data, avcC.count > 1 else { return false }
        let profile = avcC[avcC.startIndex + 1]
        return [66, 77, 100].contains(profile)
    }

    /// SDR: BT.709 primaries, transfer function and matrix.
    static var colorProperties: [String: Any] {
        [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
    }

    /// Decoded frames as 8-bit 4:2:0 in BT.709. Asking the reader for BT.709 is what converts
    /// other colour spaces, and tone-maps HDR (HLG, PQ) down to SDR.
    static var decodingSettings: [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            AVVideoColorPropertiesKey: colorProperties,
        ]
    }

    /// H.264 High at the source's frame size and frame rate.
    ///
    /// The bit rate allows 0.15 bits per pixel per frame, which looks clean at any size, but
    /// never more than twice the source's rate: H.264 needs about that much more than HEVC for
    /// the same picture, and more would only make the file bigger.
    static func encodingSettings(for size: CMVideoDimensions, frameRate: Double, sourceDataRate: Double) -> [String: Any] {
        let frameRate = frameRate > 0 ? frameRate : 30
        var bitRate = Double(size.width) * Double(size.height) * frameRate * 0.15
        if sourceDataRate > 0 { bitRate = min(bitRate, sourceDataRate * 2) }
        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoColorPropertiesKey: colorProperties,
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAverageBitRateKey: bitRate.rounded(),
                AVVideoExpectedSourceFrameRateKey: frameRate.rounded(),
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
            ] as [String: Any],
        ]
    }
}
