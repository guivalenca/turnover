import Dispatch
import Foundation

/// Ctrl-C, handled: instead of dying mid-write, turnover runs `handler` (which cancels the batch)
/// and carries on until every job has stopped and cleaned up after itself.
@MainActor
final class Interruption {
    private(set) var happened = false
    private let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)

    private init() {}

    static func onCtrlC(_ handler: @escaping @MainActor () -> Void) -> Interruption {
        let interruption = Interruption()
        signal(SIGINT, SIG_IGN)  // so that the signal reaches the source instead of ending the process
        interruption.source.setEventHandler {
            MainActor.assumeIsolated {
                interruption.happened = true
                handler()
            }
        }
        interruption.source.resume()
        return interruption
    }
}
