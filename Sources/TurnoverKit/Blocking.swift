import Dispatch

/// Runs `work`, which blocks for a while (decoding or encoding an image), on a dispatch queue,
/// and waits for it without holding one of Swift concurrency's threads.
///
/// There is one such thread per core, shared by everything async in the process: cancelling a
/// job, a video's transcode, the ring's estimates. Work that holds one for long starves the rest,
/// and the batch runner converts one image per core at once.
///
/// For work that throws, return a `Result` and `get()` it.
func blocking<T: Sendable>(_ qos: DispatchQoS.QoSClass, _ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: qos).async { continuation.resume(returning: work()) }
    }
}

extension DispatchQoS.QoSClass {
    /// The class Swift concurrency runs a task of `priority` at, so that work moved off its threads
    /// keeps the priority it had.
    init(_ priority: TaskPriority) {
        self = DispatchQoS.QoSClass(rawValue: qos_class_t(rawValue: UInt32(priority.rawValue))) ?? .default
    }
}
