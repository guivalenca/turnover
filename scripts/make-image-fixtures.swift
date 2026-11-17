// Generates the still-image and document fixtures in Tests/TurnoverTestSupport/Fixtures.
// Run through scripts/make-fixtures.sh, which also makes the WebP and the videos.
// Usage: swift scripts/make-image-fixtures.swift <output-folder>
//
// Every picture is drawn upright with a pure red 32×32 marker in its top-left corner,
// so a test can tell whether an output is the right way up.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

/// Draws the upright test picture: a sky gradient, a few discs and the red top-left marker.
func drawPicture(width: Int, height: Int, space: CGColorSpace, opaque: Bool = true) -> CGImage {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let w = CGFloat(width), h = CGFloat(height)
    if opaque {
        let gradient = CGGradient(
            colorsSpace: space,
            colors: [CGColor(red: 0.10, green: 0.25, blue: 0.55, alpha: 1),
                     CGColor(red: 0.55, green: 0.80, blue: 0.95, alpha: 1)] as CFArray,
            locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])
    }
    // A deterministic scatter of discs, so lossy encoders have some detail to work on.
    var seed: UInt32 = 7
    func next() -> CGFloat { seed = seed &* 1_103_515_245 &+ 12345; return CGFloat((seed >> 16) & 0x7FFF) / 32767 }
    for _ in 0..<40 {
        let r = 4 + next() * 18
        ctx.setFillColor(CGColor(red: next(), green: next(), blue: next(), alpha: opaque ? 1 : 0.8))
        ctx.fillEllipse(in: CGRect(x: 40 + next() * (w - 60), y: next() * (h - 40), width: r, height: r))
    }
    // Pure red marker in the top-left corner (CoreGraphics' origin is bottom-left).
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: h - 32, width: 32, height: 32))
    return ctx.makeImage()!
}

/// Rotates an upright picture 90° counter-clockwise, which is how a camera stores a portrait
/// shot tagged with EXIF orientation 6 ("rotate 90° clockwise to display").
func storedForOrientation6(_ upright: CGImage) -> CGImage {
    let ctx = CGContext(
        data: nil, width: upright.height, height: upright.width, bitsPerComponent: 8, bytesPerRow: 0,
        space: upright.colorSpace!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: CGFloat(upright.height), y: 0)
    ctx.rotate(by: .pi / 2)
    ctx.draw(upright, in: CGRect(x: 0, y: 0, width: upright.width, height: upright.height))
    return ctx.makeImage()!
}

func write(_ image: CGImage, to name: String, type: UTType, properties: [CFString: Any]) {
    let url = out.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, properties as CFDictionary)
    precondition(CGImageDestinationFinalize(dest), "could not write \(name)")
    print("wrote \(name)")
}

let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

// photo-rotated.heic: an iPhone-style portrait photo. Stored landscape (256×192) with
// orientation 6, so it displays as 192×256. Display P3, EXIF and GPS (the Eiffel Tower).
write(
    storedForOrientation6(drawPicture(width: 192, height: 256, space: p3)),
    to: "photo-rotated.heic", type: .heic,
    properties: [
        kCGImageDestinationLossyCompressionQuality: 0.6,
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyTIFFDictionary: [
            kCGImagePropertyTIFFMake: "Turnover",
            kCGImagePropertyTIFFModel: "Fixture Camera",
            kCGImagePropertyTIFFOrientation: 6,
        ],
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: "2024:06:15 10:30:00",
            kCGImagePropertyExifLensModel: "Fixture Lens 4.2mm f/1.8",
        ],
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 48.8584,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 2.2945,
            kCGImagePropertyGPSLongitudeRef: "E",
            kCGImagePropertyGPSAltitude: 35.0,
        ],
    ])

// photo.jpg: an ordinary upright sRGB JPEG with EXIF, 256×192.
write(
    drawPicture(width: 256, height: 192, space: srgb), to: "photo.jpg", type: .jpeg,
    properties: [
        kCGImageDestinationLossyCompressionQuality: 0.7,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Turnover", kCGImagePropertyTIFFModel: "Fixture Camera"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2023:12:24 18:00:00"],
    ])

// transparent.png: sRGB with an alpha channel (discs and the marker on a clear background), 256×192.
write(drawPicture(width: 256, height: 192, space: srgb, opaque: false), to: "transparent.png", type: .png, properties: [:])

// opaque.png: the opaque picture as PNG, used as the WebP source by make-fixtures.sh. Not committed.
write(drawPicture(width: 256, height: 192, space: srgb), to: "opaque.png", type: .png, properties: [:])

// document.pdf: a one-page PDF, the "non-media" file the Finder menu must ignore.
do {
    var box = CGRect(x: 0, y: 0, width: 200, height: 100)
    let ctx = CGContext(out.appendingPathComponent("document.pdf") as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    ctx.fill(CGRect(x: 20, y: 20, width: 160, height: 60))
    ctx.endPDFPage()
    ctx.closePDF()
    print("wrote document.pdf")
}
