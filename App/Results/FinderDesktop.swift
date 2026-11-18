import AppKit
import os
import TurnoverKit
import TurnoverAppCore

private let desktopLog = Logger(subsystem: "com.guivalenca.turnover", category: "desktop")

/// Puts a batch's new files where the ring was dropped on the Desktop (#18), each as it lands:
/// on the free grid spot nearest the drop with Snap to Grid, exactly there without it.
///
/// Only Finder can move a Desktop icon, so this asks it over Apple Events (`set desktop
/// position`), after asking where the other icons are to find its grid. The first time, macOS
/// asks whether Turnover may control Finder. If the answer is no, the files stay where Finder
/// put them; no window opens either way. A Desktop Finder keeps sorted is left to Finder.
@MainActor
final class FinderDesktop {
    /// The user's Desktop folder.
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop", isDirectory: true)

    /// A ring drop on the Desktop, and how the Desktop was laid out then.
    private struct Drop: Sendable {
        let id: Int
        let point: CGPoint
        let layout: DesktopLayout
    }

    private var drops = 0
    /// Files waiting to be sent to Finder together, with their drops.
    private var pending: [(file: URL, drop: Drop)] = []
    private var flush: DispatchWorkItem?
    /// One request to Finder at a time, off the main actor: the first one waits for the
    /// permission prompt.
    private let finderQueue = DispatchQueue(label: "com.guivalenca.turnover.finder-desktop", qos: .userInitiated)

    /// Moves each of `batch`'s new files that is saved on the Desktop near `point` (Finder
    /// desktop coordinates), as it lands.
    func place(_ batch: Batch, from point: CGPoint) {
        let layout = Self.layout(containing: point)
        guard layout.arrangement != .keptArranged else {
            desktopLog.notice("The Desktop is kept sorted: Finder places the new files itself")
            return
        }
        drops += 1
        let drop = Drop(id: drops, point: point, layout: layout)
        for job in batch.jobs {
            Task {
                await job.waitUntilFinished()
                guard let output = job.result?.output,
                      !ResultHandling.placeable([output], desktopFolder: Self.folder).isEmpty
                else { return }
                enqueue(output, for: drop)
            }
        }
    }

    /// Gathers files that land together into one request.
    private func enqueue(_ file: URL, for drop: Drop) {
        pending.append((file, drop))
        flush?.cancel()
        let flush = DispatchWorkItem { [weak self] in self?.send() }
        self.flush = flush
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: flush)
    }

    private func send() {
        let requests = pending
        pending = []
        var groups: [(drop: Drop, files: [URL])] = []
        for request in requests {
            if let index = groups.firstIndex(where: { $0.drop.id == request.drop.id }) {
                groups[index].files.append(request.file)
            } else {
                groups.append((request.drop, [request.file]))
            }
        }
        guard !groups.isEmpty else { return }
        finderQueue.async { [groups] in
            for group in groups { Self.move(group.files, for: group.drop) }
        }
    }

    /// Asks Finder where the Desktop's other icons are, works out where `files` go, and moves
    /// them there.
    nonisolated private static func move(_ files: [URL], for drop: Drop) {
        var icons: [CGPoint] = []
        if drop.layout.arrangement == .grid {
            guard let all = desktopIcons() else { return }
            let moving = Set(files.map { $0.lastPathComponent.precomposedStringWithCanonicalMapping })
            icons = all.filter { !moving.contains($0.name) }.map(\.position)
        }
        let points = drop.layout.places(for: files.count, droppedAt: drop.point, icons: icons)
        guard points.count == files.count else { return }
        desktopLog.debug("Other icons on the Desktop: \(icons.map(text).joined(separator: " "), privacy: .public)")
        desktopLog.notice("Dropped at \(text(drop.point), privacy: .public) on a \(String(describing: drop.layout.arrangement), privacy: .public) Desktop with \(icons.count) other icon(s): moving \(files.count) file(s) to \(points.map(text).joined(separator: " "), privacy: .public)")
        let placements = Array(zip(files, points))
        guard setPositions(placements, attempt: "first") else { return }
        // Finder may notice a file only after the first request and then put it in its own
        // next free spot. Setting the same positions again once it surely has is harmless.
        Thread.sleep(forTimeInterval: 0.6)
        setPositions(placements, attempt: "again")
    }

    nonisolated private static func text(_ point: CGPoint) -> String {
        "\(Int(point.x.rounded())),\(Int(point.y.rounded()))"
    }

    // MARK: Talking to Finder

    /// The name and desktop position of every icon on the Desktop, or nil when Finder refused.
    nonisolated private static func desktopIcons() -> [(name: String, position: CGPoint)]? {
        guard let said = osascript(readScript, arguments: [], what: "read the Desktop") else { return nil }
        return said.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, let x = Double(fields[0]), let y = Double(fields[1]) else { return nil }
            return (String(fields[2]).precomposedStringWithCanonicalMapping, CGPoint(x: x, y: y))
        }
    }

    /// Asks Finder to move each file, and logs where it says they are. Returns false when
    /// Finder refused, for example because Turnover may not control it.
    @discardableResult
    nonisolated private static func setPositions(_ placements: [(file: URL, at: CGPoint)], attempt: String) -> Bool {
        let arguments = placements.flatMap {
            [String(Int($0.at.x.rounded())), String(Int($0.at.y.rounded())), $0.file.path]
        }
        guard let said = osascript(moveScript, arguments: arguments, what: "place \(placements.count) file(s) (\(attempt))")
        else { return false }
        desktopLog.notice("Placed \(placements.count) file(s) on the Desktop (\(attempt, privacy: .public)): Finder says \(said, privacy: .public)")
        return true
    }

    /// Runs `script` with `arguments` and returns what it printed, or nil after logging why
    /// it failed.
    ///
    /// Paths and points go to `osascript` as arguments, never into the script's text.
    /// `osascript` runs as Turnover's child, so the permission prompt names Turnover.
    nonisolated private static func osascript(_ script: [String], arguments: [String], what: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = script.flatMap { ["-e", $0] } + arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            desktopLog.error("Couldn't run osascript to \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            desktopLog.error("Finder didn't \(what, privacy: .public): \(error, privacy: .public)")
            return nil
        }
        return said.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Prints a line for each icon on the Desktop: x, y and name, between tabs. Asks for all
    /// positions and names at once, or item by item if one of them has no position.
    nonisolated private static let readScript = [
        "on run argv",
        "  tell application \"Finder\"",
        "    try",
        "      set ps to desktop position of every item of desktop",
        "      set ns to name of every item of desktop",
        "    on error",
        "      set ps to {}",
        "      set ns to {}",
        "      repeat with f in (get every item of desktop)",
        "        try",
        "          set p to desktop position of f",
        "          set n to name of f",
        "          set end of ps to p",
        "          set end of ns to n",
        "        end try",
        "      end repeat",
        "    end try",
        "  end tell",
        "  set out to \"\"",
        "  repeat with i from 1 to (count ps)",
        "    set p to item i of ps",
        "    set out to out & (item 1 of p as text) & tab & (item 2 of p as text) & tab & (item i of ns) & linefeed",
        "  end repeat",
        "  return out",
        "end run",
    ]

    /// `argv` is x, y and path for each file. Prints each file's desktop position afterwards.
    nonisolated private static let moveScript = [
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

    // MARK: Finder's settings and the screen

    /// The Desktop's arrangement and icon sizes from Finder's settings, and the screen `point`
    /// is on.
    private static func layout(containing point: CGPoint) -> DesktopLayout {
        let settings = UserDefaults(suiteName: "com.apple.finder")?
            .dictionary(forKey: "DesktopViewSettings")?["IconViewSettings"] as? [String: Any]
        func number(_ key: String, _ fallback: CGFloat) -> CGFloat {
            (settings?[key] as? NSNumber).map { CGFloat($0.doubleValue) } ?? fallback
        }
        return DesktopLayout(
            arrangement: .init(finderSetting: settings?["arrangeBy"] as? String),
            screen: screen(containing: point),
            iconSize: number("iconSize", 64),
            textSize: number("textSize", 12))
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
