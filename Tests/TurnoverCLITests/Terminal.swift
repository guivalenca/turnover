import Darwin
import Foundation

/// Runs `turnover` with standard error on a pseudo-terminal, as when someone types the command
/// in Terminal. Standard output stays a pipe. In `errors`, line ends are "\r\n".
///
/// Uses posix_spawn rather than Process so that every descriptor is closed exactly once, here:
/// other tests run in parallel in this process, and a stray second close would hit whatever file
/// they opened in the meantime.
func turnoverInTerminal(_ arguments: String...) throws -> Run {
    try turnoverInTerminal(arguments)
}

/// The same, sending SIGINT (as Ctrl-C does) once what the terminal shows satisfies `interruptWhen`.
func turnoverInTerminal(_ arguments: [String], interruptWhen: (@Sendable (String) -> Bool)? = nil) throws -> Run {
    var controller: Int32 = -1, terminal: Int32 = -1
    guard openpty(&controller, &terminal, nil, nil, nil) == 0 else { throw POSIXError(.ENXIO) }
    defer { close(controller) }
    var output: [Int32] = [-1, -1]
    guard pipe(&output) == 0 else { close(terminal); throw POSIXError(.EMFILE) }
    defer { close(output[0]) }

    // The child gets /dev/null, the pipe and the terminal as 0, 1 and 2, and nothing else.
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_adddup2(&actions, output[1], 1)
    posix_spawn_file_actions_adddup2(&actions, terminal, 2)
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    // Signals the test runner ignores would stay ignored in the child: reset SIGINT, as a shell does.
    var defaults = sigset_t()
    sigemptyset(&defaults)
    sigaddset(&defaults, SIGINT)
    posix_spawnattr_setsigdefault(&attributes, &defaults)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF))

    let executable = productsDirectory.appendingPathComponent("turnover").path
    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    var pid: pid_t = 0
    let spawned = posix_spawn(&pid, executable, &actions, &attributes, argv, environ)
    // The child has its own copies now. Closing ours lets reads end when it exits.
    close(output[1])
    close(terminal)
    guard spawned == 0 else { throw POSIXError(POSIXErrorCode(rawValue: spawned) ?? .ENOEXEC) }

    // Drain the terminal while the command runs, so a full buffer never blocks it.
    let drained = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var shown = Data()
    let screen = controller
    let child = pid
    DispatchQueue.global().async {
        var interrupted = false
        shown = readAll(screen) { soFar in
            guard !interrupted, let interruptWhen, interruptWhen(String(decoding: soFar, as: UTF8.self)) else { return }
            interrupted = true
            kill(child, SIGINT)
        }
        drained.signal()
    }
    let out = readAll(output[0])
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    drained.wait()
    return Run(status: (status >> 8) & 0xFF,
               output: String(decoding: out, as: UTF8.self),
               errors: String(decoding: shown, as: UTF8.self))
}

/// Reads until end of file, or the error a terminal gives once its other end is closed, passing
/// everything read so far to `onRead` after each read.
private func readAll(_ descriptor: Int32, onRead: (Data) -> Void = { _ in }) -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = read(descriptor, &buffer, buffer.count)
        if count > 0 { data.append(contentsOf: buffer[..<count]); onRead(data) }
        else if count < 0 && errno == EINTR { continue }
        else { return data }
    }
}
