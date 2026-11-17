import Dispatch

/// Runs `work`, which blocks for a while (decoding or encoding an image), on a dispatch queue,
/// and waits for it without holding one of Swift concurrency's threads. There is one such thread
/// per core, and other work, the app's included, needs them meanwhile.
func blocking<T: Sendable>(_ qos: DispatchQoS.QoSClass, _ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: qos).async { continuation.resume(returning: work()) }
    }
}
