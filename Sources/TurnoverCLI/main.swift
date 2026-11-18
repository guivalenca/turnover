import Foundation
import TurnoverKit

// Exit codes: 0 when every file converted (files of another kind are only skipped), 1 when any
// failed, 64 (EX_USAGE) for a bad command line, 130 when interrupted with Ctrl-C.

func printError(_ message: String) {
    FileHandle.standardError.write(Data("turnover: \(message)\n".utf8))
}

if CommandLine.arguments.dropFirst().first == "offers" {
    exit(await OffersCommand.run(Array(CommandLine.arguments.dropFirst(2))))
}

let parsed: Command.Parsed
do {
    parsed = try Command.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    printError(error.message)
    FileHandle.standardError.write(Data((Command.usage + "\n").utf8))
    exit(64)
}

switch parsed {
case .help:
    print(Command.usage)
case .convert(let files, let action):
    let sources = files.map { URL(fileURLWithPath: $0).absoluteURL.standardizedFileURL }
    let line = ProgressLine.isAvailable
        ? ProgressLine(label: sources.count == 1 ? sources[0].lastPathComponent : "\(sources.count) files", jobs: sources.count)
        : nil
    var reporting: (@Sendable (Int, Double) -> Void)?
    if let line { reporting = { job, fraction in line.report(job, fraction) } }
    let batch = JobRunner().run(sources, to: [action], reporting: reporting)
    let interrupted = Interruption.onCtrlC { batch.cancel() }

    // Report in the order given, as each job ends; the others keep running meanwhile.
    var failed = false
    for (index, job) in batch.jobs.enumerated() {
        await job.waitUntilFinished()
        var skipped = false
        let report: () -> Void
        switch job.state {
        case .converted(let result):
            report = { print(result.output.path) }
        case .skipped(.notApplicable(let file, let format)):
            skipped = true
            report = { printError("\(file.lastPathComponent): skipped, can't be converted to \(format.name)") }
        case .skipped(let reason):
            skipped = true
            failed = true
            report = { printError(reason.localizedDescription) }
        case .failed(let reason):
            failed = true
            report = { printError(reason.localizedDescription) }
        case .cancelled, .waiting, .running:
            report = {}
        }
        if let line {
            line.clearing(report)
            line.ended(index, skipped: skipped)
        } else {
            report()
        }
    }
    exit(interrupted.happened ? 130 : failed ? 1 : 0)
}
