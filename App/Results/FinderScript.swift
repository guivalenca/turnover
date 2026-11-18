import Foundation
import os

/// Asks Finder something over Apple Events, with a small AppleScript run by `osascript`. The
/// first time, macOS asks whether Turnover may control Finder; if the answer is no, every
/// request fails and its caller does without.
enum FinderScript {
    /// Runs `script` with `arguments` and returns what it printed, or nil after logging to `log`
    /// why it failed. Blocks until Finder answers: call it off the main actor.
    ///
    /// Paths and points go to `osascript` as arguments, never into the script's text.
    /// `osascript` runs as Turnover's child, so the permission prompt names Turnover.
    static func run(_ script: [String], arguments: [String], what: String, log: Logger) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = script.flatMap { ["-e", $0] } + arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            log.error("Couldn't run osascript to \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            log.error("Finder didn't \(what, privacy: .public): \(error, privacy: .public)")
            return nil
        }
        return said.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
