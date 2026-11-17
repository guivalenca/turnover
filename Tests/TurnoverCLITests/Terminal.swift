import Darwin
import Foundation

/// Runs `turnover` with standard error on a pseudo-terminal, as when someone types the command
/// in Terminal. Standard output stays a pipe. In `errors`, line ends are "\r\n".
func turnoverInTerminal(_ arguments: String...) throws -> Run {
    var controller: Int32 = -1, terminal: Int32 = -1
    guard openpty(&controller, &terminal, nil, nil, nil) == 0 else { throw POSIXError(.ENXIO) }
    let screen = FileHandle(fileDescriptor: controller, closeOnDealloc: true)

    let process = Process()
    process.executableURL = productsDirectory.appendingPathComponent("turnover")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle(fileDescriptor: terminal, closeOnDealloc: true)
    try process.run()
    close(terminal)  // The child has its own copy; reading the controller ends when it exits.

    // Drain the terminal while the command runs, so a full buffer never blocks it.
    let drained = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var shown = Data()
    let reading = controller
    DispatchQueue.global().async {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while case let count = read(reading, &buffer, buffer.count), count > 0 {
            shown.append(contentsOf: buffer[..<count])
        }
        drained.signal()
    }
    let out = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    drained.wait()
    _ = screen
    return Run(status: process.terminationStatus,
               output: String(decoding: out, as: UTF8.self),
               errors: String(decoding: shown, as: UTF8.self))
}
