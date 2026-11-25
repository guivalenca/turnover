@preconcurrency import AVFoundation
import Foundation

extension ScratchFolder {
    /// Writes a one-second H.264 MP4 at up to 12 Mbit/s: coloured stripes that slide sideways, with
    /// plenty left to compress. The fixtures are tiny and have next to nothing left, so tests of
    /// making a video smaller make their own. `turned`: played turned 90° clockwise. `still`: the
    /// stripes don't move, so nothing is left to compress.
    @discardableResult
    public func addBusyMP4(width: Int, height: Int, turned: Bool = false, still: Bool = false, as name: String) async throws -> URL {
        let file = url.appendingPathComponent(name)
        let writer = try AVAssetWriter(outputURL: file, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000],
        ])
        if turned { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData, writer.status == .writing { try await Task.sleep(for: .milliseconds(2)) }
            // Not from the adaptor's pool, which comes and goes with the writer's state.
            var created: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &created)
            guard writer.status == .writing, let buffer = created
            else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let row = CVPixelBufferGetBytesPerRow(buffer)
            let pixels = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt32.self)
            // One row of 8 × 8 blocks at a time, copied down: quick enough in a debug build.
            let shift = still ? 0 : frame * 5
            for top in stride(from: 0, to: height, by: 8) {
                let line = pixels + top * row / 4
                let offset = shift * (1 + top / 8 % 3)
                var x = -(offset % 8)
                while x < width {
                    let block = UInt32((x + offset) / 8) &* 73_856_093 ^ UInt32(top / 8) &* 19_349_663
                    let shade = (block &* 2_654_435_761) >> 26  // 0 to 63
                    var colour = 0xFF00_0000 | (90 + shade) << 16 | (80 + shade) << 8 | (100 + shade)
                    let start = max(0, x), end = min(width, x + 8)
                    memset_pattern4(line + start, &colour, (end - start) * 4)
                    x += 8
                }
                for y in (top + 1)..<max(top + 1, min(top + 8, height)) { memcpy(pixels + y * row / 4, line, width * 4) }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
            else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return file
    }
}
