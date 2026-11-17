import Foundation
import TurnoverKit

// Exit codes: 0 when every file converted, 1 when any failed, 64 (EX_USAGE) for a bad command line.

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
    var failed = false
    for path in files {
        let source = URL(fileURLWithPath: path).absoluteURL.standardizedFileURL
        let line = ProgressLine.isAvailable ? ProgressLine(for: source) : nil
        do {
            let result = try await Converter().convert(source, with: action) { line?.show($0) }
            line?.clear()
            print(result.output.path)
        } catch let error as ConversionError {
            line?.clear()
            printError(error.localizedDescription)
            failed = true
        } catch {
            line?.clear()
            printError("\(source.lastPathComponent): \(error.localizedDescription)")
            failed = true
        }
    }
    exit(failed ? 1 : 0)
}
