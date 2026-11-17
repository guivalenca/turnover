# Turnover

**Turn Apple's files into formats everyone can open, right from Finder.**

iPhones and Macs save videos as `.mov` and photos as `.heic`. Turnover is a small macOS app that converts them in place:

- **Right-click → Turnover ›** MP4, PNG or JPEG.
- **Drag a file and press ⇧**: a glass ring opens under your cursor; drop on a format.

The converted file appears next to the original, which is never touched.

> **Status: work in progress.** The right-click menu works; the ring, settings and notifications are on their way.

## Planned for v1

- Videos (`.mov`, `.m4v`) → **MP4** (H.264, plays everywhere; instant when the video is already H.264).
- Images (HEIC, HEIF, WebP, AVIF, TIFF, PNG, JPEG) → **PNG** or **JPEG**.
- Keeps dates, EXIF, colour profile and orientation. Never overwrites anything.
- Native Swift app for macOS 15 and later, built from source with `make install`.

## Install from source

You need a Mac with macOS 15 or later and Xcode. No Apple developer account is needed: the app is signed locally.

```sh
git clone https://github.com/guivalenca/turnover.git
cd turnover
make install
```

This builds Turnover, copies it to `/Applications`, turns on its Finder extension and starts it. Run it again to upgrade. `make uninstall` removes it.

If the Turnover item doesn't show up in Finder, turn on Turnover in **System Settings › General › Login Items & Extensions**, under Extensions.

## License

[MIT](LICENSE)
