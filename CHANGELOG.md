# Changelog

What changed in each version of Turnover. Versions follow [semantic versioning](https://semver.org).

## Unreleased

- **Images from the web:** drag an image out of a page in Safari, Chrome or Dia and press ⇧. The ring's centre says what it is (`WebP · 1600 × 1067`), and a drop saves it as PNG, as JPEG, or as it is with the new **Original** entry. Dropped over the Desktop it lands there, over a Finder window in that window's folder, and anywhere else in Downloads. Over another app it is also copied, ready to paste with ⌘V. Nothing is downloaded and no browser extension is needed: the image is read from the drag itself.

## 1.0.0 — 2026-11-18

The first release, built from the spec in [#1](https://github.com/guivalenca/turnover/issues/1).

### Converting

- Photos to **PNG**, or **JPEG** at Best (100%), High (85%) or Small (60%): HEIC, HEIF, AVIF, WebP, TIFF, PNG, JPEG and most other images macOS opens. Dates, EXIF, location and colour profile are kept, and the orientation is applied ([#3](https://github.com/guivalenca/turnover/issues/3), [#4](https://github.com/guivalenca/turnover/issues/4)).
- Videos to **MP4** that plays everywhere: H.264 is copied without re-encoding, anything else (HEVC, HDR, uncommon H.264 profiles) becomes 8-bit H.264 with AAC audio ([#5](https://github.com/guivalenca/turnover/issues/5)).
- New files appear next to the originals, numbered when the name is taken, whole or not at all. A read-only folder falls back to Downloads ([#7](https://github.com/guivalenca/turnover/issues/7)).
- Images convert in parallel, videos two at a time, and a cancelled conversion leaves nothing behind ([#7](https://github.com/guivalenca/turnover/issues/7)).

### In Finder

- **Turnover ›** in the right-click menu, with the formats that fit the selection ([#8](https://github.com/guivalenca/turnover/issues/8)).
- **The ring:** drag files, press ⇧, and drop on a format. Each format shows the size of its output, exact for photos ([#6](https://github.com/guivalenca/turnover/issues/6), [#11](https://github.com/guivalenca/turnover/issues/11), [#17](https://github.com/guivalenca/turnover/issues/17)). Hold ⌥ for the JPEG qualities, and rest on a format to add it for mixed selections ([#12](https://github.com/guivalenca/turnover/issues/12)). It is drawn in Liquid Glass on macOS 26 and later ([#13](https://github.com/guivalenca/turnover/issues/13)).
- Converted from a Finder window, the new files are selected in it. Dropped on the ring on the Desktop, they appear where the ring was dropped, on Finder's grid, and no Finder window opens ([#18](https://github.com/guivalenca/turnover/issues/18)).

### The app

- A background app with no Dock icon, which opens at login, and a window with the setup checklist and settings ([#9](https://github.com/guivalenca/turnover/issues/9)).
- Progress in the menu bar for longer conversions, with a stop button per job, and notifications when they finish or fail ([#10](https://github.com/guivalenca/turnover/issues/10)).
- The blue ring icon, in every appearance, and a menu bar glyph ([#14](https://github.com/guivalenca/turnover/issues/14)).
- `make install` signs with a free Apple Development certificate when there is one, so macOS asks for each permission once ([#19](https://github.com/guivalenca/turnover/issues/19)).
- No Accessibility, Input Monitoring or Screen Recording access needed ([#2](https://github.com/guivalenca/turnover/issues/2)).

### Command line

- `turnover <files…> --to png|jpeg|mp4` and `turnover offers [--exact] <files…>` ([#3](https://github.com/guivalenca/turnover/issues/3), [#6](https://github.com/guivalenca/turnover/issues/6)).
