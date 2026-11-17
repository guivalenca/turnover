import Foundation

/// The committed test fixtures. See Fixtures/README.md for what each one contains and how to
/// regenerate them. Never write next to `url`: copy a fixture into a `ScratchFolder` first.
public enum Fixture: String, CaseIterable, Sendable {
    /// Portrait HEIC stored landscape with EXIF orientation 6: 256×192 stored, 192×256 upright.
    /// Display P3, EXIF (DateTimeOriginal, LensModel), TIFF Make/Model, GPS (48.8584 N, 2.2945 E).
    case heicRotated = "photo-rotated.heic"
    /// Upright sRGB JPEG with EXIF, 256×192.
    case jpeg = "photo.jpg"
    /// sRGB PNG with transparency, 256×192.
    case png = "transparent.png"
    /// Lossy WebP, 256×192.
    case webp = "photo.webp"
    /// 2 s H.264 + AAC QuickTime movie, 160×90 at 30 fps.
    case movH264 = "clip-h264.mov"
    /// The same H.264 + AAC streams in an MPEG-4 container.
    case mp4H264 = "clip-h264.mp4"
    /// 2 s 10-bit HEVC HLG (HDR) + AAC QuickTime movie, stored 160×90 with a 90° matrix (plays 90×160).
    case movHEVCHDR = "clip-hevc-hdr.mov"
    /// The `movH264` video with 16-bit PCM audio (8 kHz mono), and iPhone-style QuickTime metadata:
    /// recorded 2024-06-15T10:30:00+0200 at +48.8584+002.2945+035.000/.
    case movH264PCM = "clip-h264-pcm.mov"
    /// The `movH264` video with no audio track.
    case movH264Silent = "clip-h264-silent.mov"
    /// A one-page PDF. ImageIO can decode it, but it is not an image.
    case pdf = "document.pdf"
    /// Plain text.
    case text = "notes.txt"

    /// The read-only committed file.
    public var url: URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent(rawValue)
    }

    /// The file's bytes, for "unchanged" comparisons.
    public var data: Data { try! Data(contentsOf: url) }
}
