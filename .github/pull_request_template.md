<!-- What changes, and why. -->


<!--
Release checklist: for a pull request into `main`. On any other pull request, delete everything below.

CI covers conversions and the ring's logic. The checks below need a person, a real mouse and keyboard,
and Finder. Use copies of real photos and videos in a folder you made for the test. Tick what passed,
and write what didn't under the item.
-->

## Release checklist

Tested on: macOS ___ (Mac: ___ , display: ___ ) and macOS 15.___

### Install

- [ ] On a fresh clone, with only Xcode, `make install` installs to `/Applications` and opens the Turnover window in front, with keyboard focus.
- [ ] Running `make install` again upgrades in place, and System Settings › General › Login Items & Extensions lists a single Turnover.
- [ ] No Dock icon. No menu bar item while nothing is converting.
- [ ] After a first install, macOS shows "Login Item Added" once.
- [ ] With an Apple Development certificate in the keychain, `make install` prints "signed with a certificate"; without one, it says it signed ad hoc and that macOS will ask again after each reinstall.

### Setup window

- [ ] Opening Turnover from Applications or Spotlight while it runs brings the window to the current Space.
- [ ] **Finder extension** reads On. Turn Turnover off in System Settings › General › Login Items & Extensions: within a second or two the row shows Open Settings…, which opens that page. Turn it back on: the row reads On again.
- [ ] **Notifications** › Allow… shows the system prompt. Allow: the row reads Allowed. Don't Allow instead: the button becomes Open Settings…, which opens Turnover's page in Notifications.
- [ ] **JPEG quality**: the choice survives a relaunch, and right-click › JPEG uses it.
- [ ] ⌘W closes the window and Turnover keeps running. ⌘Q and Quit Turnover quit it.
- [ ] VoiceOver reads every row and control.

### Login item

- [ ] Open at login is on after the first install. Log out and back in: Turnover is running, with no window.
- [ ] Turn Open at login off, log out and in: Turnover isn't running. Turn it on again.
- [ ] With the window open, turn Turnover off in System Settings › General › Login Items: the switch follows within a second. Turning it back on from the switch opens Login Items if macOS asks for approval.

### Finder menu

- [ ] Right-click a HEIC: **Turnover ›** sits just below Quick Actions, with PNG (1 image) and JPEG (1 image). PNG writes `name.png` next to it, selected in Finder; the original is unchanged.
- [ ] Converting the same file again writes `name 2.png`.
- [ ] Photos, a PNG, a MOV and a PDF together: PNG and JPEG with their image counts, a separator, MP4 (1 video). Each converts only the files it fits.
- [ ] An MP4 alone: Smaller MP4 (1 video), which writes `name-s.mp4`, smaller, next to it.
- [ ] A PDF or a text file alone: no Turnover item.
- [ ] Works in icon, list, column and gallery views, and on the Desktop. On the Desktop, the new file appears there and no Finder window opens.
- [ ] On an external drive and on a writable network share, the new file lands next to the original.
- [ ] On a read-only disk image, the new file goes to Downloads, with "Saved … to Downloads"; Show in Finder selects it.

### Folder access

- [ ] The first conversion on the Desktop, in Documents, in Downloads, on an external drive and on a network share each asks once. After allowing, the conversion goes ahead.
- [ ] After another `make install` signed with a certificate, none of them is asked again. Signed ad hoc (`make install SIGN_IDENTITY=-`), they come back once, and nothing else breaks.

### The ring: drag and ⇧

With a physical mouse or trackpad, and the keyboard:

- [ ] Drag a photo in Finder and press ⇧: the ring opens under the pointer. Release ⇧: it closes and the drag carries on; a drop into a folder moves the file as usual.
- [ ] ⇧ held before the drag starts opens no ring. Releasing ⇧ and pressing it again does.
- [ ] ⇧-click, ⇧ with the arrow keys and ⇧ box-select in Finder select as before, with no ring.
- [ ] The ring opens for drags from a Finder window in icon, list and column view, from the Desktop and from a Dock stack.
- [ ] A PDF dragged with ⇧ shows a short hint by the pointer and no ring, and the drag carries on.
- [ ] A drag of hundreds of files opens the ring promptly, with the right counts.

### The ring: catching the drop

- [ ] A drop on a format converts, and the dragged files stay put. From a Finder window, the new files are selected in it. From the Desktop, they appear where you dropped: with Snap to Grid on the nearest free grid spots, lined up with the other icons; with Sort By None exactly there, in a row for several files; sorted by name or date, where Finder sorts them. No Finder window opens. From a Dock stack, nothing opens.
- [ ] The first drop on the Desktop asks once whether Turnover may control Finder. After Don't Allow, the new file goes to Finder's next free spot, still with no window.
- [ ] A drop on the centre, off the ring, or off the ring over a Finder folder or the Desktop cancels: the files slide back and nothing moves.
- [ ] Esc during the drag cancels it, and the ring closes after the slide-back.
- [ ] With two displays: moving from the ring's screen to the other doesn't close it, and a drop on the other screen is refused.
- [ ] Near a screen edge, under the menu bar or the notch, above the Dock, and in a full-screen Space, the ring stays whole on screen.

### The ring: ⌥ and mixed drags

- [ ] Hold ⌥ over the ring: JPEG fans out into Best, High and Small, each with its size, and the default is marked. Releasing ⌥ folds them back. A drop on a quality uses it this once, and the setting doesn't change.
- [ ] ⌥ then ⇧, ⇧ then ⌥, and both at once all work. A drag started with ⌥ (a Finder copy) then ⇧ opens the ring fanned out, and the drop converts rather than copies.
- [ ] Release ⇧ while holding ⌥: a drop into a folder copies, as usual.
- [ ] An MP4 alone opens High, Medium and Small with their sizes, Medium marked, and a drop converts at that quality. With a MOV or photos alongside, it is one entry, Smaller, which ⌥ fans out.
- [ ] Photos and a video together: the caption reads "Rest on a format to add it, then drop on another". Rest on PNG: it fills, blinks ✓ and stays tinted. Over MP4 the centre reads "PNG + MP4 · 2 files", and the drop converts both.
- [ ] Dropping straight on MP4 converts only the video. Adding JPEG after PNG replaces it.
- [ ] Change the spring-loading speed (System Settings › Accessibility › Pointer Control): the rest delay follows it from the next drag. The 0.5 s default feels right.

### The ring: images from the web

In Safari and in Chrome (and Dia, if installed), with a page of photos and an image search:

- [ ] Drag an image and press ⇧: the ring opens with PNG, JPEG and Original, and the centre reads its type and size in pixels, such as "WebP" over "1600 × 1067". Sizes appear within a moment. A JPEG offers PNG and Original only; a PNG, JPEG and Original.
- [ ] Without ⇧, the drag behaves as before: onto the Desktop, into a Finder window, into another app. Release ⇧ over the ring and it carries on the same way.
- [ ] A drop on PNG over the browser saves `name.png` in Downloads: "Saved to Downloads" shows by the pointer, the Dock's Downloads stack bounces, and the clipboard is unchanged. Again: `name 2.png`.
- [ ] A drop on Original saves the image byte for byte under its own extension (compare with the browser's Save Image As).
- [ ] A drop over the bare Desktop puts the new file where you dropped it, as for a drag of Desktop files, and no Finder window opens.
- [ ] A drop over a Finder window saves into the folder it shows, selected. The first time, macOS asks whether Turnover may control Finder; after Don't Allow, and over a Recents or search window, it goes to Downloads with the note.
- [ ] A drop over another app (Mail, Messages, a chat) reads "Saved to Downloads · Copied", and ⌘V attaches the new file there.
- [ ] Over the ring, the drag image shrinks to a small picture of the image as soon as the pointer moves, and doesn't stay large over the centre.
- [ ] An image inside a link (a search result) is named after its title, not the link. With neither a name nor a title, it is `image.png`.
- [ ] ⌥ fans JPEG out with Original still at the bottom. Esc, a drop on the centre and a drop off the ring cancel, and nothing is saved.
- [ ] Dragging a link, selected text, or an SVG image and pressing ⇧: no ring (the SVG shows a hint), and the drag carries on.
- [ ] After each of these, `ls $TMPDIR | grep Turnover-dragged` lists nothing.

### The ring: look and drag image

- [ ] Over the ring, the drag image shrinks to a small thumbnail without its name, and comes back when the ring closes: in icon, list and column view, from the Desktop, and with many files.
- [ ] macOS 26 and later: Liquid Glass; the tinted highlight springs to the format under the pointer. Readable over light and dark windows, in light and dark mode.
- [ ] macOS 15: the ring uses the translucent material and reads as clearly.
- [ ] Reduce Transparency, Increase Contrast and Reduce Motion (System Settings › Accessibility › Display): still readable; with Reduce Motion, nothing grows or springs.
- [ ] Accent colours other than blue, including Graphite, tint the highlight and its label.
- [ ] Sizes appear within a moment, then lose their "~" when exact. MP4 reads "Instant" for a small H.264 video, "About N s" for a large one (copying it takes a few seconds), and "About N s" for HEVC.

### Menu bar item and stopping

- [ ] A conversion that takes a few seconds (several 4K HEVC videos): the item appears after about a second with a percentage, rises to 100%, and goes about 1.5 s after the end. A quick conversion never shows it.
- [ ] Its menu lists running and waiting files. ✕ stops one, leaving no partial file, and the others carry on. Stop All stops the rest. With more than 8 left, it reads "N more waiting".
- [ ] Esc closes the open menu.
- [ ] The glyph reads well in light and dark menu bars, over a colourful wallpaper, and on a notched Mac with a full menu bar.
- [ ] VoiceOver reads the item ("Turnover, 42%") and each ✕ ("Stop converting <file>").

### Notifications

- [ ] A batch that takes over about 3 s ends with "Converted 2 videos to MP4"; Show in Finder selects them. A quick batch posts nothing.
- [ ] A damaged file (a truncated HEIC) posts "Couldn't convert …" with the reason.
- [ ] With notifications turned off for Turnover, conversions still work.
- [ ] Quit Turnover, then click an earlier "Converted…" notification: Turnover opens without its window, and the files are selected.

### Output

- [ ] The MP4s play on a Windows PC, an Android phone, a TV, a web uploader and a messaging app.
- [ ] Real iPhone videos: HDR (compare with Photos' export), Cinematic, slo-mo, 4K at 60 and 120 fps, spatial audio.
- [ ] Real iPhone photos (12 and 48 MP) and Retina screenshots: upright, with location, dates and colours kept, and the ring's estimates close to the real sizes.
- [ ] The app icon in Finder, Spotlight and System Settings, with each icon style in System Settings › Appearance: Default, Dark, Clear and Tinted.

### Uninstall

- [ ] `make uninstall` removes the app, the Turnover menu and the ring. System Settings › General › Login Items no longer lists Turnover.
