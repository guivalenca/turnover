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
    let batch = JobRunner().run(sources, to: [action])
    let interrupted = Interruption.onCtrlC { batch.cancel() }
    let line = ProgressLine.isAvailable
        ? ProgressLine(label: sources.count == 1 ? sources[0].lastPathComponent : "\(sources.count) files")
        : nil
    line?.follow(batch)

    // Report in the order given, as each job ends; the others keep running meanwhile.
    var failed = false
    for job in batch.jobs {
        await job.waitUntilFinished()
        line?.clear()
        switch job.state {
        case .converted(let result):
            print(result.output.path)
        case .skipped(.notApplicable(let file, let format)):
            printError("\(file.lastPathComponent): skipped, can't be converted to \(format)")
        case .skipped(let reason):
            printError(reason.localizedDescription)
            failed = true
        case .failed(let reason):
            printError(reason)
            failed = true
        case .cancelled, .waiting, .running:
            break
        }
    }
    exit(interrupted.happened ? 130 : failed ? 1 : 0)
}
