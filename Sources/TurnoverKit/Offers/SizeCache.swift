import Foundation
import Synchronization

/// Exact output sizes already measured, per file, so a second drag of the same photo is exact at
/// once. A file is the same while its path, size and modification date are; any change to it
/// (or a new file at the path) makes a new key, and the old entry ages out.
///
/// Holds at most `capacity` files, forgetting the least recently used first. An entry is a few
/// numbers, so a thousand files take well under a megabyte.
final class SizeCache: Sendable {
    struct Key: Hashable, Sendable {
        let path: String
        let size: Int
        let modified: Date

        /// Nil when the file can't be read.
        init?(_ url: URL) {
            // A fresh URL: one that has been asked before may answer from its own cache.
            let file = URL(fileURLWithPath: url.path)
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let modified = values.contentModificationDate
            else { return nil }
            (path, self.size, self.modified) = (url.standardizedFileURL.path, size, modified)
        }
    }

    private struct State {
        var entries: [Key: (sizes: ImageSizes, lastUse: UInt64)] = [:]
        var clock: UInt64 = 0
    }

    let capacity: Int
    private let state = Mutex(State())

    init(capacity: Int) {
        self.capacity = max(0, capacity)
    }

    /// The exact sizes known for the file at `key`, if any.
    func sizes(for key: Key) -> ImageSizes? {
        state.withLock { state in
            guard let entry = state.entries[key] else { return nil }
            state.clock += 1
            state.entries[key]!.lastUse = state.clock
            return entry.sizes
        }
    }

    /// Remembers that `output` of the `pixels`-pixel image at `key` takes exactly `bytes`.
    func store(_ output: ImageOutput, bytes: Int, pixels: Int, for key: Key) {
        guard capacity > 0 else { return }
        state.withLock { state in
            state.clock += 1
            var sizes = state.entries[key]?.sizes ?? ImageSizes(pixels: pixels, sizes: [:])
            sizes.sizes[output] = ImageSizes.Size(bytes: bytes, isExact: true)
            state.entries[key] = (sizes, state.clock)
            if state.entries.count > capacity,
               let oldest = state.entries.min(by: { $0.value.lastUse < $1.value.lastUse })?.key {
                state.entries[oldest] = nil
            }
        }
    }
}
