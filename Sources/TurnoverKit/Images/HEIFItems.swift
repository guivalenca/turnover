import Foundation

/// HEIC, HEIF and AVIF files keep their pictures as items whose bytes the `meta` box's `iloc`
/// box locates. ImageIO opens such a file cut short and decodes the missing bytes as whatever
/// it finds, and the JPEG encoder never notices, so it would "convert" to a blank picture. A
/// cut file is caught here instead, from the boxes alone, before anything is decoded: the same
/// check `MovieSource` makes for movies.
enum HEIFItems {
    /// False when the file at `url` is an ISO base media file (it starts with `ftyp`) whose
    /// `meta` box, or the bytes of one of its items, lie past the end of the file. True for any
    /// other file, which this can't judge.
    static func areComplete(in url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= 8 else { return true }
        var offset: UInt64 = 0
        var isFirst = true
        while offset + 8 <= size {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let header = try? handle.read(upToCount: 16), header.count >= 8
            else { return false }
            var reader = Reader(header)
            var boxSize = UInt64(reader.integer(4))
            let type = reader.fourCC()
            var headerSize: UInt64 = 8
            if isFirst, type != "ftyp" { return true }  // not an ISO base media file
            isFirst = false
            if boxSize == 1 {
                boxSize = reader.integer(8)
                headerSize = 16
            } else if boxSize == 0 {
                boxSize = size - offset  // runs to the end of the file
            }
            guard !reader.overran, boxSize >= headerSize else { return false }
            if type == "meta" {
                guard offset + boxSize <= size, boxSize - headerSize <= maxMetaSize,
                      (try? handle.seek(toOffset: offset + headerSize)) != nil,
                      let meta = try? handle.read(upToCount: Int(boxSize - headerSize)),
                      meta.count == Int(boxSize - headerSize)
                else { return false }
                return itemsFit(meta: meta, fileSize: size)
            }
            offset += boxSize
        }
        return true
    }

    /// A `meta` box holds the item table and properties: kilobytes, even for a big tiled photo.
    private static let maxMetaSize: UInt64 = 16 << 20

    /// Whether every item `meta` (the box's contents) locates in this file ends within it.
    private static func itemsFit(meta: Data, fileSize: UInt64) -> Bool {
        var reader = Reader(meta)
        reader.skip(4)  // version and flags: `meta` is a full box
        while reader.remaining >= 8 {
            let start = reader.position
            let boxSize = Int(reader.integer(4))
            let type = reader.fourCC()
            guard boxSize >= 8, start + boxSize <= meta.count else { return false }
            if type == "iloc" {
                return locationsFit(Reader(meta[(start + 8)..<(start + boxSize)]), fileSize: fileSize)
            }
            reader.skip(boxSize - 8)
        }
        return true  // no item table: nothing to check
    }

    /// ISO/IEC 14496-12, `ItemLocationBox`.
    private static func locationsFit(_ box: Reader, fileSize: UInt64) -> Bool {
        var reader = box
        let version = reader.integer(1)
        reader.skip(3)  // flags
        let sizes = reader.integer(1), moreSizes = reader.integer(1)
        let (offsetSize, lengthSize) = (Int(sizes >> 4), Int(sizes & 0xF))
        let baseOffsetSize = Int(moreSizes >> 4)
        let indexSize = version == 1 || version == 2 ? Int(moreSizes & 0xF) : 0
        let itemCount = reader.integer(version < 2 ? 2 : 4)
        for _ in 0..<itemCount {
            reader.skip(version < 2 ? 2 : 4)  // item ID
            // 0: bytes in a file; 1 and 2 (in the meta box, or in another item) are checked by
            // the boxes or items they point into.
            let construction = version == 1 || version == 2 ? reader.integer(2) & 0xF : 0
            let dataReference = reader.integer(2)  // 0: this file
            let base = reader.integer(baseOffsetSize)
            let extents = reader.integer(2)
            for _ in 0..<extents {
                reader.skip(indexSize)
                let offset = reader.integer(offsetSize), length = reader.integer(lengthSize)
                guard !reader.overran else { return false }
                if construction == 0, dataReference == 0, base + offset + length > fileSize { return false }
            }
            guard !reader.overran else { return false }
        }
        return !reader.overran
    }

    /// Reads big-endian fields, noting rather than trapping when it runs past the end.
    private struct Reader {
        private let bytes: [UInt8]
        private(set) var position = 0
        private(set) var overran = false

        init(_ data: some Collection<UInt8>) {
            bytes = Array(data)
        }

        var remaining: Int { max(0, bytes.count - position) }

        mutating func skip(_ count: Int) {
            position += count
            if position > bytes.count { overran = true }
        }

        /// An unsigned integer `size` bytes long (0 to 8).
        mutating func integer(_ size: Int) -> UInt64 {
            guard position + size <= bytes.count else {
                overran = true
                position = bytes.count
                return 0
            }
            var value: UInt64 = 0
            for byte in bytes[position..<(position + size)] { value = value << 8 | UInt64(byte) }
            position += size
            return value
        }

        mutating func fourCC() -> String {
            let value = integer(4)
            return String(decoding: (0..<4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * $0)) }, as: UTF8.self)
        }
    }
}
