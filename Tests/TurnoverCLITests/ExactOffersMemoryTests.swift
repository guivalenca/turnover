import Darwin
import Foundation
import Testing
import TurnoverTestSupport

/// Refining measures a bounded number of photos, one at a time, so a big selection of big photos
/// takes no more memory than one of them.
@Suite(.timeLimit(.minutes(3))) struct ExactOffersMemory {
    let folder = try! ScratchFolder()

    @Test func refiningTenBigPhotosTakesNoMoreMemoryThanOne() async throws {
        let first = try await offThePool { try folder.addMosaic(of: .heicRotated, width: 8064, height: 6048, as: "1.jpg") }
        let photos = try [first] + (2...10).map { index in
            let copy = folder.url.appendingPathComponent("\(index).jpg")
            try FileManager.default.copyItem(at: first, to: copy)
            return copy
        }

        let one = try await offThePool { try peakMemory(ofTurnover: ["offers", "--exact", first.path]) }
        let ten = try await offThePool { try peakMemory(ofTurnover: ["offers", "--exact"] + photos.map(\.path)) }

        #expect(one.status == 0 && ten.status == 0)
        // About what converting one of them to PNG takes: the decoded photo plus the PNG (about
        // 600 MB here, 485 MB on CI). Measuring them all at once would take over 2 GB.
        #expect(ten.bytes < 1_000_000_000, "\(ten.bytes / 1_000_000) MB")
        #expect(Double(ten.bytes) < Double(one.bytes) * 1.5, "\(one.bytes / 1_000_000) MB, then \(ten.bytes / 1_000_000) MB")
    }
}

/// Runs `turnover` with no input or output and returns its exit status and the most memory it
/// had resident at once. Uses posix_spawn and wait4, which reports the child's own peak, whatever
/// other tests run meanwhile.
func peakMemory(ofTurnover arguments: [String]) throws -> (status: Int32, bytes: Int) {
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    for descriptor: Int32 in [0, 1, 2] {
        posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", descriptor == 0 ? O_RDONLY : O_WRONLY, 0)
    }
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

    let executable = productsDirectory.appendingPathComponent("turnover").path
    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    var pid: pid_t = 0
    let spawned = posix_spawn(&pid, executable, &actions, &attributes, argv, environ)
    guard spawned == 0 else { throw POSIXError(POSIXErrorCode(rawValue: spawned) ?? .ENOEXEC) }
    var status: Int32 = 0
    var usage = rusage()
    while wait4(pid, &status, 0, &usage) == -1 && errno == EINTR {}
    // ru_maxrss is in bytes on macOS.
    return ((status >> 8) & 0xFF, usage.ru_maxrss)
}

/// Runs `work`, which blocks for seconds, on a dispatch queue, keeping Swift concurrency's few
/// threads (three on CI) free for the tests running alongside.
func offThePool<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(with: Result { try work() }) }
    }
}
