# Test fixtures

Shared by every test target through `TurnoverTestSupport` (`Fixture.heicRotated.url`, …).
They are committed, not generated at test time, because CI runners may lack HEIC and HEVC
encoders. Regenerate or extend them with `scripts/make-fixtures.sh` (needs ffmpeg and cwebp),
then commit the files. Keep the folder well under 1 MB. The script rewrites every file; with the
same tools, all come out identical except `document.pdf` and `clip-h264-pcm.mov`, which carry
their creation time, so commit only the files you meant to change.

Every picture is drawn upright with a pure red 32×32 marker in its top-left corner.

| File | What it is | Used for |
| --- | --- | --- |
| `photo-rotated.heic` | iPhone-style portrait HEIC: stored 256×192 with EXIF orientation 6, so 192×256 upright. Display P3. EXIF `DateTimeOriginal` 2024:06:15 10:30:00, `LensModel`; TIFF Make "Turnover", Model "Fixture Camera"; GPS 48.8584 N, 2.2945 E, altitude 35 | orientation, profile and metadata preservation |
| `photo.jpg` | Upright sRGB JPEG, 256×192, EXIF `DateTimeOriginal` 2023:12:24 18:00:00 | JPEG input, JPEG → JPEG refused |
| `transparent.png` | sRGB PNG with alpha, 256×192 | PNG → PNG refused, transparency |
| `photo.webp` | Lossy WebP, 256×192 | any ImageIO-readable image converts |
| `clip-h264.mov` | 2 s, 160×90, 30 fps, H.264 High + AAC mono, QuickTime | MP4 pass-through |
| `clip-h264.mp4` | The same streams in MPEG-4 | MP4 → MP4 refused |
| `clip-h264-pcm.mov` | The `clip-h264.mov` video with 16-bit PCM audio (8 kHz mono), plus iPhone-style QuickTime (`mdta`) metadata: `creationdate` 2024-06-15T10:30:00+0200, `location.ISO6709` +48.8584+002.2945+035.000/. The metadata is added by `scripts/tag-movie.swift` | MP4 with the video passed through and the audio encoded to AAC; metadata kept |
| `clip-h264-silent.mov` | The `clip-h264.mov` video with no audio track | MP4 of a silent video |
| `clip-hevc-hdr.mov` | 2 s, 10-bit HEVC Main10, HLG BT.2020 (HDR), + AAC mono. Stored 160×90 with a 90° clockwise matrix: plays as 90×160 portrait | MP4 transcode, HDR → SDR, portrait |
| `document.pdf` | One-page PDF. ImageIO decodes it, but it must be *unsupported* | non-media input |
| `notes.txt` | Plain text | non-media input |
