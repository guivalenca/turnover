// Copies a movie, streams untouched, adding the QuickTime metadata an iPhone writes: the
// recording date and location, in the `mdta` key space. ffmpeg can't write these keys in a way
// AVFoundation reads back, so make-fixtures.sh calls this instead.
//
// usage: swift scripts/tag-movie.swift <in.mov> <out.mov> <ISO 8601 date> <ISO 6709 location>

import AVFoundation

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    print("usage: swift tag-movie.swift <in.mov> <out.mov> <ISO 8601 date> <ISO 6709 location>")
    exit(64)
}
let source = URL(fileURLWithPath: arguments[1])
let destination = URL(fileURLWithPath: arguments[2])
try? FileManager.default.removeItem(at: destination)

func item(_ key: String, _ value: String) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.keySpace = .quickTimeMetadata
    item.key = key as NSString
    item.value = value as NSString
    item.dataType = kCMMetadataBaseDataType_UTF8 as String
    return item
}

let export = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough)!
export.metadata = [
    item("com.apple.quicktime.creationdate", arguments[3]),
    item("com.apple.quicktime.location.ISO6709", arguments[4]),
]
try await export.export(to: destination, as: .mov)
