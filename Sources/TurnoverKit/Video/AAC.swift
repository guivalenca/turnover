import AVFoundation
import CoreMedia

/// What "plays everywhere" means for audio: AAC-LC, mono or stereo, at most 48 kHz.
enum AAC {
    /// Whether an audio stream can go into the MP4 untouched.
    static func isWidelyPlayable(_ format: CMFormatDescription) -> Bool {
        format.mediaSubType == .mpeg4AAC
    }

    /// Decoded audio, mixed down to stereo and resampled to 48 kHz when the source has more.
    static func decodingSettings(for format: CMFormatDescription) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatLinearPCM].merging(shape(of: format)) { $1 }
    }

    /// AAC-LC at the decoded audio's sample rate and channel count; the encoder picks the bit rate.
    static func encodingSettings(for format: CMFormatDescription) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC].merging(shape(of: format)) { $1 }
    }

    private static func shape(of format: CMFormatDescription) -> [String: Any] {
        let source = format.audioStreamBasicDescription
        let sampleRate = min(source?.mSampleRate ?? 48_000, 48_000)
        let channels = min(max(Int(source?.mChannelsPerFrame ?? 2), 1), 2)
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
        return [
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
        ]
    }
}
