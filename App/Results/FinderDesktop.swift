import AppKit
import os
import TurnoverKit
import TurnoverAppCore

private let desktopLog = Logger(subsystem: "com.guivalenca.turnover", category: "desktop")

/// Puts a batch's new files where the ring was dropped on the Desktop (#18), each as it lands.
///
/// Only Finder can move a Desktop icon, so this asks it over Apple Events (`set desktop
/// position`). The first time, macOS asks whether Turnover may control Finder. If the answer is
/// no, the files stay where Finder put them; no window opens either way.
@MainActor
final class FinderDesktop {
    /// The user's Desktop folder.
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop", isDirectory: true)

    /// Files waiting to be sent to Finder together, with their slots.
    private var pending: [(file: URL, at: CGPoint)] = []
    private var flush: DispatchWorkItem?
    /// One request to Finder at a time, off the main actor: the first one waits for the
    /// permission prompt.
    private let finderQueue = DispatchQueue(label: "com.guivalenca.turnover.finder-desktop", qos: .userInitiated)

    /// Moves each of `batch`'s new files that is saved on the Desktop to the next slot from
    /// `drop` (Finder desktop coordinates), in the order they land.
    func place(_ batch: Batch, from drop: CGPoint) {
        let slots = Slots(DesktopSlots(drop: drop, pitch: Self.pitch(), screen: Self.screen(containing: drop)))
        for job in batch.jobs {
            Task {
                await job.waitUntilFinished()
                guard let output = job.result?.output,
                      !ResultHandling.placeable([output], desktopFolder: Self.folder).isEmpty
                else { return }
                enqueue(output, at: slots.value.next())
            }
        }
    }

    /// One batch's slots, shared by its jobs as they land.
    @MainActor private final class Slots {
        var value: DesktopSlots
        init(_ value: DesktopSlots) { self.value = value }
    }

    /// Gathers files that land together into one request.
    private func enqueue(_ file: URL, at point: CGPoint) {
        pending.append((file, point))
        flush?.cancel()
        let flush = DispatchWorkItem { [weak self] in self?.send() }
        self.flush = flush
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: flush)
    }

    private func send() {
        let placements = pending
        pending = []
        guard !placements.isEmpty else { return }
        finderQueue.async {
            guard Self.runFinder(placements, attempt: "first") else { return }
            // Finder may notice a file only after the first request and then put it in its own
            // next free slot. Setting the same positions again once it surely has is harmless.
            Thread.sleep(forTimeInterval: 0.6)
            Self.runFinder(placements, attempt: "again")
        }
    }

    /// Asks Finder to move each file, and logs where it says they are. Returns false when
    /// Finder refused, for example because Turnover may not control it.
    ///
    /// The paths and points go to `osascript` as arguments, never into the script's text.
    /// `osascript` runs as Turnover's child, so the permission prompt names Turnover.
    @discardableResult
    nonisolated private static func runFinder(_ placements: [(file: URL, at: CGPoint)], attempt: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = script.flatMap { ["-e", $0] } + placements.flatMap {
            [String(Int($0.at.x.rounded())), String(Int($0.at.y.rounded())), $0.file.path]
        }
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            desktopLog.error("Couldn't run osascript: \(error.localizedDescription, privacy: .public)")
            return false
        }
        process.waitUntilExit()
        let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            desktopLog.error("Finder didn't place \(placements.count) file(s) (\(attempt, privacy: .public)): \(error, privacy: .public)")
            return false
        }
        let asked = placements.map { "\(Int($0.at.x)),\(Int($0.at.y))" }.joined(separator: " ")
        desktopLog.notice("Placed \(placements.count) file(s) on the Desktop (\(attempt, privacy: .public)): asked \(asked, privacy: .public), Finder says \(said, privacy: .public)")
        return true
    }

    /// `argv` is x, y and path for each file. Prints each file's desktop position afterwards.
    nonisolated private static let script = [
        "on run argv",
        "  set placed to \"\"",
        "  tell application \"Finder\"",
        "    repeat with i from 1 to (count argv) by 3",
        "      set f to (POSIX file (item (i + 2) of argv)) as alias",
        "      set desktop position of f to {(item i of argv) as integer, (item (i + 1) of argv) as integer}",
        "      set p to desktop position of f",
        "      set placed to placed & (item 1 of p as text) & \",\" & (item 2 of p as text) & \" \"",
        "    end repeat",
        "  end tell",
        "  return placed",
        "end run",
    ]

    // MARK: Finder's grid and the screen

    /// The distance between slots, from Finder's Desktop view settings.
    private static func pitch() -> CGSize {
        let settings = UserDefaults(suiteName: "com.apple.finder")?
            .dictionary(forKey: "DesktopViewSettings")?["IconViewSettings"] as? [String: Any]
        func number(_ key: String, _ fallback: Double) -> Double {
            (settings?[key] as? NSNumber)?.doubleValue ?? fallback
        }
        return DesktopSlots.pitch(
            iconSize: number("iconSize", 64), gridSpacing: number("gridSpacing", 54), textSize: number("textSize", 12))
    }

    /// The visible frame, in Finder desktop coordinates, of the screen `point` is on.
    private static func screen(containing point: CGPoint) -> CGRect {
        let coordinates = DesktopCoordinates.current
        let screens = NSScreen.screens
        let screen = screens.first { coordinates.topLeft($0.frame).contains(point) } ?? screens.first
        return screen.map { coordinates.topLeft($0.visibleFrame) } ?? .null
    }
}

extension DesktopCoordinates {
    /// For the screens as they are now.
    @MainActor static var current: DesktopCoordinates {
        DesktopCoordinates(mainScreenHeight: NSScreen.screens.first?.frame.height ?? 0)
    }
}
