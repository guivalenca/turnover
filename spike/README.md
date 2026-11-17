# Spike: the three macOS integration risks (ticket #2)

Throwaway code on `spike/macos-risks`. It is never merged. The verdicts are in the comment on issue #1.

## What is here

| Path | What it proves |
|---|---|
| `project.yml` | XcodeGen spec: LSUIElement app + embedded Finder Sync extension, both signed **ad hoc** (`CODE_SIGN_IDENTITY: "-"`, no team). |
| `TurnoverSpike/DragWatcher.swift` | Risk 1. Detects a drag from another app (drag pasteboard `changeCount`) and ⇧ pressed after it started (`NSEvent.modifierFlags` poll + global `flagsChanged` monitor). No Accessibility, no Input Monitoring. |
| `TurnoverSpike/RingPanel.swift` | Risk 2. Full-screen, transparent, non-activating `NSPanel` shown mid-drag. It is the drag destination, reads the file URLs from `NSDraggingInfo`, accepts on the target, refuses elsewhere, and replaces the drag images with small icons. Glass disc via `NSGlassEffectView`. |
| `TurnoverSpikeFinder/FinderSync.swift` | Risk 3. `FIFinderSync` that adds a top-level "Turnover ›" submenu and forwards the choice to the app over the `turnover-spike://` URL scheme. Writes no files. |
| `TurnoverSpike/Main.swift` | Agent entry point, URL-scheme receiver (`convert`, `status`, `manage-extensions`, `quit`), permission logging. |
| `tools/spikectl.swift` | Test driver run from a shell trusted for Accessibility: finds Finder items with AX and posts short bursts of synthesized input. |
| `tools/burst.sh`, `tools/tests/*.zsh` | The Finder test scenarios. Each burst waits until the user has been idle, then restores the front app and cursor. |

## Build and run

```sh
brew install xcodegen
./build.sh                                   # xcodegen + xcodebuild (ad hoc) + spikectl; prints signatures
open -g build/Debug/TurnoverSpike.app        # registers the app and its appex with LaunchServices/pluginkit
pluginkit -e use -i com.guivalenca.turnover.spike.finder
log stream --style compact --level debug --predicate 'subsystem == "com.guivalenca.turnover.spike"'
```

Launch it with `open` so the app gets its own TCC identity. A binary started from a terminal inherits the terminal's Accessibility trust and proves nothing.

## Clean up

```sh
open -g "turnover-spike://quit"
pluginkit -e ignore -i com.guivalenca.turnover.spike.finder
pluginkit -r build/Debug/TurnoverSpike.app/Contents/PlugIns/TurnoverSpikeFinder.appex
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u build/Debug/TurnoverSpike.app
tccutil reset All com.guivalenca.turnover.spike
defaults delete com.guivalenca.turnover.spike
rm -rf build ~/Library/Containers/com.guivalenca.turnover.spike.finder
```
