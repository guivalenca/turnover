# Turnover

**Turn the `.heic` photos and `.mov` videos from your iPhone and Mac into PNG, JPEG and MP4, right from Finder.**

![Right-click a photo and choose Turnover › PNG. Then drag a photo and a video, press ⇧, rest on JPEG to add it, and drop on MP4.](docs/demo.gif)

## Using Turnover

**Right-click** photos or videos in Finder and choose **Turnover ›** PNG, JPEG or MP4.

**Drag** them and press **⇧**. A ring of formats opens under the pointer: drop on one. The files you dragged stay where they are.

- Hold **⌥** over the ring to choose the JPEG quality for this drop only: Best, High or Small.
- Dragging photos and videos together? **Rest** on a format for a moment to add it (it fills and shows ✓), then drop on another. Drop straight on one format to convert only that kind of file.
- To cancel, drop anywhere off the ring or press Esc. Release ⇧ to carry on with a normal drag.

The new file appears next to the original, with the same name, and is selected in Finder. Turnover never changes or overwrites a file.

| From | To |
| --- | --- |
| Videos: MOV, M4V | **MP4**: H.264 and AAC, which play everywhere. Instant when the video is already H.264 (a large one takes a few seconds, the time to copy it); otherwise it is re-encoded at the same size and frame rate, with HDR mapped to SDR. H.264 that not every player decodes (High 10, 4:2:2, 4:4:4) is re-encoded too. |
| Images: HEIC, HEIF, AVIF, WebP, TIFF, PNG, JPEG and most others macOS opens | **PNG**, or **JPEG** at Best (100%), High (85%, the default) or Small (60%) |

- Dates, EXIF, location and colour profile are kept, and the orientation is applied.
- If the name is taken, the new file is numbered, like `IMG_0420 2.jpg`. If the folder is read-only, the new file goes to Downloads and Turnover tells you.
- Quick conversions just appear. Longer ones show a percentage in the menu bar, where you can stop them, and a notification tells you when they're done. Failures always notify.

## Requirements

- macOS 15 or later
- Xcode 26 or later, free from the Mac App Store

No Apple developer account is needed: `make install` signs the app on your Mac.

## Install

```sh
git clone https://github.com/guivalenca/turnover.git
cd turnover
make install
```

This builds Turnover, copies it to `/Applications`, turns on its Finder extension and opens it. To upgrade, run `git pull` and `make install` again. If it stops with "xcodebuild requires Xcode", run `sudo xcode-select -s /Applications/Xcode.app` first.

Turnover runs in the background, with no Dock icon, and opens at login. Open it from Applications or Spotlight to see its window: setup, JPEG quality, Open at login, and Quit.

### The first time

macOS asks a few things once:

- **Login Item Added:** a notification that Turnover opens at login. You can turn that off in Turnover's window.
- **Notifications:** asked the first time Turnover has something to tell you, or when you click Allow… in its window.
- **Folder access:** the first time you convert a file on the Desktop, in Documents or Downloads, on an external drive or on a network share, macOS asks whether Turnover may access it. Allow it. Because the app is signed on your Mac rather than by a developer, macOS treats each `make install` as a new app, so these prompts come back after every reinstall or upgrade.

If **Turnover ›** is missing from the right-click menu, click Open Settings… next to Finder extension in Turnover's window and turn Turnover on.

Turnover needs no Accessibility or Input Monitoring access.

## Uninstall

```sh
make uninstall
```

This quits Turnover, turns off its Finder extension, deletes the app, and resets its permissions and settings. macOS keeps the extension's empty folder, `~/Library/Containers/com.guivalenca.turnover.finder`; you can delete it in Finder.

## Command line

The `turnover` command converts like the app does. Build it from the clone:

```sh
swift build -c release --product turnover
.build/release/turnover IMG_0420.HEIC --to png
```

Copy `.build/release/turnover` to a folder on your `PATH` to use it anywhere.

```text
turnover <files…> --to png|jpeg|mp4 [--quality best|high|small]
turnover offers [--exact] <files…>
```

- Each new file is saved next to its original, and its path is printed.
- The exit code is 1 if any file couldn't be converted, and 64 for a usage error.
- `--quality` is for JPEG; the default is `high`.
- `offers` lists the formats each file can become, with estimated sizes and times, and converts nothing. With `--exact`, it waits for the exact image sizes the ring ends up showing (measured by encoding a few photos in memory; the others are scaled from them).
- Ctrl-C stops the conversions and leaves nothing behind.

## How it works

- **TurnoverKit**, a Swift package, does the converting with ImageIO and AVFoundation, and no third-party code. Each file is written to a temporary file and then moved next to the original, so a cancelled or failed conversion leaves nothing behind.
- **Turnover.app** is a background app. It runs the conversions, the menu bar progress, the notifications and the ring.
- **The Finder extension** builds the Turnover › menu and passes your choice to the app as a `turnover://` link. It never converts or writes files.
- **The ring** watches the mouse and modifier keys, which needs no permission. When you press ⇧ during a file drag, a transparent full-screen panel becomes the drop target and reads the files from the drag itself. The ring is drawn in Liquid Glass, or the system's translucent material on macOS 15. Its behaviour is `RingModel`, a state machine with its own tests.

## Contributing

| Folder | What |
| --- | --- |
| `Sources/TurnoverKit` | Inspection, offers and estimates, conversion actions, output placement, the batch runner. The Finder extension, the app and the command all use it |
| `Sources/TurnoverAppCore` | The app's own rules, kept out of the extension: launch, settings, Open at login, the menu bar item's timing and the notifications |
| `Sources/RingModel` | The ring's behaviour, without AppKit |
| `Sources/TurnoverCLI` | The `turnover` command |
| `App`, `FinderExtension` | The app and the Finder Sync extension |
| `Tests` | Swift Testing suites, and small committed fixtures |

- `make test` runs every test: TurnoverKit, the app core, the ring model and the command line. CI runs them on every push and builds the app. Before Swift 6.4 (Xcode 27), a plain `swift test` uses SwiftPM's older build system, which doesn't compile the String Catalogs: run `make test`, or `swift test --build-system swiftbuild`.
- `Turnover.xcodeproj` is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`, and committed so that building needs only Xcode. After you edit `project.yml`, or add, move or remove a file under `App/` or `FinderExtension/`, run `make project` (`brew install xcodegen`). CI fails if the committed project doesn't match, and changes made in Xcode's project editor are lost on the next `make project`.
- `make app` builds `build/Turnover.app` without installing it.
- Running the app from Xcode registers a second copy of it and its Finder extension. Run `make install` afterwards so that only the installed copy answers.
- A new output format is a `ConversionAction` (images in `Sources/TurnoverKit/Actions`, videos in `Sources/TurnoverKit/Video`) plus a case in `OutputFormat`, which gives it its name and its `--to` value. The compiler then points at the few places that list every format: the Finder extension's menu action, the "already a PNG" reason, and, for an image format, its size estimates.
- User-facing text lives in each target's `Localizable.xcstrings` (TurnoverKit, TurnoverAppCore, RingModel and the app), in English for now. Counts use the catalogs' plural forms. The command's own messages are English only.

Automated tests can't drive Finder, the ring or the system prompts. Before each release, go through the [manual checklist](.github/pull_request_template.md) in the pull request into `main`.

## Licence

MIT. See [LICENSE](LICENSE).
