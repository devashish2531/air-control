// IconTool.swift — app-icon generator for Air Control.
//
// Turns a square piece of source artwork that already carries its own rounded-rect
// shape (with white or transparent corners) into:
//   * iOS  — a full-bleed, opaque, sRGB 1024x1024 icon (no alpha; the OS masks it).
//   * macOS — the ten-file legacy icon set: the artwork drawn into the system
//     rounded-rect body on a transparent canvas, with Apple's drop shadow.
//
// The interesting step is `expandToEdges`: the exterior background (white or
// transparent, found by flood fill from the image border) is repainted by
// growing the artwork outward from its own boundary. That makes the artwork a
// full opaque square without cropping any of the composition away, so both the
// iOS mask and the macOS body shape can be applied cleanly on top of it.
//
// Usage:
//   IconTool ios  <source.png> <out.png> [--grayscale] [--inset <pct>] [--size <px>]
//   IconTool mac  <source.png> <outDir>
//
// Build:  swiftc -O -o icontool IconTool.swift

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Geometry constants (measured from macOS 26 system icons)

/// Full canvas of the macOS master render.
private let macCanvas = 1024.0
/// The icon body occupies 824x824 centred in that canvas (100 px margin each side).
private let macBody = 824.0
/// Continuous ("squircle") corner radius of the body. Calibrated against
/// Notes/Maps/Music/Xcode on macOS 26: r=215 reproduces their alpha profile
/// to an RMS of 0.6 px.
private let macCornerRadius = 215.0

// MARK: - Bitmap

/// A straight-through sRGB RGBA8 buffer. All sources here are fully opaque or
/// opaque-plus-transparent-margin, so premultiplied and straight alpha agree.
struct Bitmap {
    var width: Int
    var height: Int
    var pixels: [UInt8] // RGBA, row-major

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("IconTool: \(message)\n".utf8))
    exit(1)
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func loadCGImage(_ path: String) -> CGImage {
    guard let data = NSData(contentsOfFile: path),
          let source = CGImageSourceCreateWithData(data, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("cannot read image at \(path)") }
    return image
}

/// Rasterise into a known sRGB RGBA8 layout regardless of the file's own profile.
func rasterize(_ image: CGImage) -> Bitmap {
    var bitmap = Bitmap(width: image.width, height: image.height)
    let width = bitmap.width, height = bitmap.height
    bitmap.pixels.withUnsafeMutableBytes { raw in
        guard let ctx = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { fail("cannot create raster context") }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return bitmap
}

/// Wrap a bitmap back into a CGImage (alpha preserved).
func makeCGImage(_ bitmap: Bitmap) -> CGImage {
    let width = bitmap.width, height = bitmap.height
    let provider = CGDataProvider(data: Data(bitmap.pixels) as CFData)!
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: sRGB,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
    )!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
    else { fail("cannot create PNG destination at \(path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("cannot write PNG at \(path)") }
}

// MARK: - Background removal / outward expansion

/// True for pixels that read as "outside the artwork": transparent, or near-white.
private func isBackgroundish(_ p: [UInt8], _ index: Int) -> Bool {
    let o = index * 4
    if p[o + 3] < 24 { return true }
    return p[o] > 236 && p[o + 1] > 236 && p[o + 2] > 236
}

/// Flood fill from the image border to find the *exterior* background only.
/// Interior near-white artwork (this icon has a white mouse dead centre) is
/// deliberately left alone — that is why this is a flood fill and not a
/// per-pixel colour test.
func exteriorMask(_ bitmap: Bitmap, erode: Int) -> [Bool] {
    let w = bitmap.width, h = bitmap.height
    var outside = [Bool](repeating: false, count: w * h)
    var stack: [Int] = []
    let px = bitmap.pixels

    func seed(_ x: Int, _ y: Int) {
        let i = y * w + x
        if !outside[i], isBackgroundish(px, i) { outside[i] = true; stack.append(i) }
    }
    for x in 0 ..< w { seed(x, 0); seed(x, h - 1) }
    for y in 0 ..< h { seed(0, y); seed(w - 1, y) }

    while let i = stack.popLast() {
        let x = i % w, y = i / w
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, ny = y + dy
            if nx < 0 || ny < 0 || nx >= w || ny >= h { continue }
            let j = ny * w + nx
            if !outside[j], isBackgroundish(px, j) { outside[j] = true; stack.append(j) }
        }
    }

    // Grow the exterior a little into the artwork so the anti-aliased rim of the
    // source's rounded corner is repainted too, instead of surviving as a pale halo.
    for _ in 0 ..< erode {
        var grown = outside
        for y in 0 ..< h {
            for x in 0 ..< w where !outside[y * w + x] {
                var touching = false
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    if nx < 0 || ny < 0 || nx >= w || ny >= h { continue }
                    if outside[ny * w + nx] { touching = true; break }
                }
                if touching { grown[y * w + x] = true }
            }
        }
        outside = grown
    }
    return outside
}

/// Repaint every exterior pixel by growing the artwork outward from its boundary,
/// one BFS level at a time, averaging the already-known neighbours. The result is
/// a smooth clamp-extension of the background gradient into the corners, so the
/// image becomes a fully opaque square with no white left anywhere.
func expandToEdges(_ bitmap: inout Bitmap, outside: [Bool]) {
    let w = bitmap.width, h = bitmap.height
    var known = outside.map { !$0 }
    var frontier: [Int] = []
    var queued = [Bool](repeating: false, count: w * h)

    func neighbours(_ i: Int, _ body: (Int) -> Void) {
        let x = i % w, y = i / w
        for dy in -1 ... 1 {
            let ny = y + dy
            if ny < 0 || ny >= h { continue }
            for dx in -1 ... 1 where dx != 0 || dy != 0 {
                let nx = x + dx
                if nx < 0 || nx >= w { continue }
                body(ny * w + nx)
            }
        }
    }

    for i in 0 ..< (w * h) where !known[i] {
        var adjacent = false
        neighbours(i) { if known[$0] { adjacent = true } }
        if adjacent { frontier.append(i); queued[i] = true }
    }

    while !frontier.isEmpty {
        var resolved: [(Int, UInt8, UInt8, UInt8)] = []
        resolved.reserveCapacity(frontier.count)
        for i in frontier {
            var r = 0, g = 0, b = 0, n = 0
            neighbours(i) { j in
                if known[j] { let o = j * 4
                    r += Int(bitmap.pixels[o]); g += Int(bitmap.pixels[o + 1]); b += Int(bitmap.pixels[o + 2]); n += 1 }
            }
            if n > 0 { resolved.append((i, UInt8(r / n), UInt8(g / n), UInt8(b / n))) }
        }
        for (i, r, g, b) in resolved {
            let o = i * 4
            bitmap.pixels[o] = r; bitmap.pixels[o + 1] = g; bitmap.pixels[o + 2] = b; bitmap.pixels[o + 3] = 255
            known[i] = true
        }
        var next: [Int] = []
        for (i, _, _, _) in resolved {
            neighbours(i) { j in
                if !known[j], !queued[j] { queued[j] = true; next.append(j) }
            }
        }
        frontier = next
    }

    for i in 0 ..< (w * h) { bitmap.pixels[i * 4 + 3] = 255 } // fully opaque square
}

/// Bounding box of the artwork (everything the exterior flood fill did not claim).
func contentBounds(_ bitmap: Bitmap, outside: [Bool]) -> (x: Int, y: Int, w: Int, h: Int) {
    let w = bitmap.width, h = bitmap.height
    var minX = w, maxX = -1, minY = h, maxY = -1
    for y in 0 ..< h {
        for x in 0 ..< w where !outside[y * w + x] {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
    if maxX < 0 { fail("no artwork found in source image") }
    return (minX, minY, maxX - minX + 1, maxY - minY + 1)
}

// MARK: - Shared pipeline

/// Load the source, repaint its exterior outward, and return the artwork as a
/// centred, opaque, square CGImage inset by `insetFraction` on every side.
func squareArtwork(source path: String, insetFraction: Double, grayscale: Bool) -> CGImage {
    var bitmap = rasterize(loadCGImage(path))
    let outside = exteriorMask(bitmap, erode: 2)
    let bounds = contentBounds(bitmap, outside: outside)
    expandToEdges(&bitmap, outside: outside)

    if grayscale {
        for i in 0 ..< (bitmap.width * bitmap.height) {
            let o = i * 4
            let y = 0.2126 * Double(bitmap.pixels[o]) + 0.7152 * Double(bitmap.pixels[o + 1])
                + 0.0722 * Double(bitmap.pixels[o + 2])
            let v = UInt8(max(0, min(255, y.rounded())))
            bitmap.pixels[o] = v; bitmap.pixels[o + 1] = v; bitmap.pixels[o + 2] = v
        }
    }

    let expanded = makeCGImage(bitmap)
    let side = Double(min(bounds.w, bounds.h))
    let inset = (side * insetFraction).rounded()
    let cropSide = side - 2 * inset
    let cropX = Double(bounds.x) + (Double(bounds.w) - side) / 2 + inset
    let cropY = Double(bounds.y) + (Double(bounds.h) - side) / 2 + inset
    guard let cropped = expanded.cropping(
        to: CGRect(x: cropX, y: cropY, width: cropSide, height: cropSide)
    ) else { fail("crop failed") }
    return cropped
}

/// Scale down by repeated halving so small sizes stay crisp instead of aliasing.
func resize(_ image: CGImage, to size: Int, opaque: Bool) -> CGImage {
    var current = image
    while current.width / 2 >= size, current.width / 2 > 0 {
        current = draw(current, into: current.width / 2, opaque: opaque)
    }
    return draw(current, into: size, opaque: opaque)
}

func draw(_ image: CGImage, into size: Int, opaque: Bool) -> CGImage {
    let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: alphaInfo.rawValue
    ) else { fail("cannot create output context") }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let out = ctx.makeImage() else { fail("cannot render output") }
    return out
}

// MARK: - iOS

func makeIOSIcon(source: String, output: String, size: Int, insetFraction: Double, grayscale: Bool) {
    let artwork = squareArtwork(source: source, insetFraction: insetFraction, grayscale: grayscale)
    // `opaque: true` gives a 24-bit PNG: the App Store rejects icons with alpha.
    writePNG(resize(artwork, to: size, opaque: true), to: output)
    print("  wrote \(output) — \(size)x\(size), opaque")
}

// MARK: - macOS

/// The macOS body shape: Apple's continuous rounded rectangle.
func macBodyPath(in rect: CGRect, radius: Double) -> CGPath {
    SwiftUI.Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath
}

/// Render the 1024 master: transparent canvas, Apple-style drop shadow, artwork
/// clipped to the body shape.
func makeMacMaster(source: String) -> CGImage {
    let artwork = squareArtwork(source: source, insetFraction: 0.0, grayscale: false)
    let side = Int(macCanvas)
    guard let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("cannot create macOS context") }
    ctx.interpolationQuality = .high

    let origin = (macCanvas - macBody) / 2
    let bodyRect = CGRect(x: origin, y: origin, width: macBody, height: macBody)
    let path = macBodyPath(in: bodyRect, radius: macCornerRadius)

    // Two shadow passes approximate the soft + contact shadow that macOS 26
    // system icons carry. The opaque fills are covered by the artwork afterwards.
    for (offsetY, blur, alpha) in [(-14.0, 30.0, 0.16), (-5.0, 10.0, 0.14)] {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: offsetY), blur: blur,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: alpha))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(artwork, in: bodyRect)
    ctx.restoreGState()

    guard let master = ctx.makeImage() else { fail("cannot render macOS master") }
    return master
}

/// The ten files declared by the appiconset's Contents.json.
let macOutputs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

func makeMacIcons(source: String, outputDirectory: String) {
    let master = makeMacMaster(source: source)
    var cache: [Int: CGImage] = [Int(macCanvas): master]
    for (name, pixels) in macOutputs {
        let image = cache[pixels] ?? resize(master, to: pixels, opaque: false)
        cache[pixels] = image
        writePNG(image, to: (outputDirectory as NSString).appendingPathComponent(name))
        print("  wrote \(name) — \(pixels)x\(pixels), transparent corners")
    }
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3 else {
    fail("""
    usage:
      IconTool ios <source.png> <out.png> [--grayscale] [--inset <fraction>] [--size <px>]
      IconTool mac <source.png> <outDir>
    """)
}

let command = arguments[0]
let sourcePath = arguments[1]
let destination = arguments[2]
var grayscale = false
var insetFraction = 0.02
var iosSize = 1024
var index = 3
while index < arguments.count {
    switch arguments[index] {
    case "--grayscale": grayscale = true; index += 1
    case "--inset":
        guard index + 1 < arguments.count, let v = Double(arguments[index + 1]) else { fail("--inset needs a number") }
        insetFraction = v; index += 2
    case "--size":
        guard index + 1 < arguments.count, let v = Int(arguments[index + 1]) else { fail("--size needs a number") }
        iosSize = v; index += 2
    default: fail("unknown option \(arguments[index])")
    }
}

switch command {
case "ios":
    makeIOSIcon(source: sourcePath, output: destination, size: iosSize,
                insetFraction: insetFraction, grayscale: grayscale)
case "mac":
    makeMacIcons(source: sourcePath, outputDirectory: destination)
default:
    fail("unknown command \(command) (expected 'ios' or 'mac')")
}
