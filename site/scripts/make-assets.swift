// make-assets.swift — regenerates the landing page's static images.
//
// Inputs : design/icons/{ios,mac}-icon-source.png (1254x1254, artwork on a white ground)
// Outputs: site/public/icon-ios.png          transparent-cornered app icon, 384 (bright)
//          site/public/icon-mac.png          transparent-cornered app icon, 384 (dark)
//          site/src/app/icon.png             favicon (512)
//          site/src/app/apple-icon.png       touch icon (180)
//          site/public/og.png                1200x630 Open Graph card
//
// Run:  site/scripts/make-assets.sh
//
// macOS-only (CoreGraphics + CoreText). CI never runs this: the PNGs are committed.

import AppKit
import CoreGraphics
import CoreText
import Foundation

// MARK: - Small helpers

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-assets: \(message)\n".utf8))
    exit(1)
}

let colorSpace = CGColorSpaceCreateDeviceRGB()

func newContext(width: Int, height: Int) -> CGContext {
    guard
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { die("could not create a \(width)x\(height) bitmap context") }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    return ctx
}

func loadImage(_ path: String) -> CGImage {
    guard
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { die("could not read \(path)") }
    return image
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    guard
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { die("could not open \(path) for writing") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { die("could not write \(path)") }
    print("  wrote \(path) (\(image.width)x\(image.height))")
}

/// RGBA8 pixel buffer for a CGImage, so we can measure the artwork inside its white margin.
struct Pixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        let ctx = newContext(width: width, height: height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { die("could not read pixels") }
        let rowBytes = ctx.bytesPerRow
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let src = data.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<(width * 4) { out[y * width * 4 + x] = src[x] }
        }
        bytes = out
    }

    /// True when the pixel is part of the artwork rather than the white/transparent surround.
    func isArtwork(_ x: Int, _ y: Int) -> Bool {
        let i = (y * width + x) * 4
        let a = bytes[i + 3]
        if a < 200 { return false }
        return !(bytes[i] > 243 && bytes[i + 1] > 243 && bytes[i + 2] > 243)
    }
}

/// The artwork's bounding box plus the corner radius of its own rounded-square shape.
/// The top row of a rounded rect spans [minX + r, maxX - r], which gives r directly.
func measureArtwork(_ px: Pixels) -> (rect: CGRect, radius: CGFloat) {
    var minX = px.width, minY = px.height, maxX = -1, maxY = -1
    for y in 0..<px.height {
        for x in 0..<px.width where px.isArtwork(x, y) {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX > minX, maxY > minY else { die("found no artwork in the source image") }

    // Walk a few rows below the top edge and take the smallest inset seen, which is the
    // flattest part of the corner arc; averaging a few rows shrugs off anti-aliasing.
    var insets: [Int] = []
    for probe in 0..<4 {
        let y = minY + probe
        guard y <= maxY else { break }
        var first = -1
        for x in minX...maxX where px.isArtwork(x, y) {
            first = x
            break
        }
        if first >= 0 { insets.append(first - minX) }
    }
    let inset = insets.min() ?? 0
    let side = CGFloat(max(maxX - minX + 1, maxY - minY + 1))
    // The measured inset is the radius at the very top of the arc; nudge it up slightly so the
    // clip eats the source's anti-aliased rim instead of leaving a white hairline.
    let radius = min(side * 0.5, CGFloat(inset) * 1.06)

    return (
        CGRect(
            x: CGFloat(minX), y: CGFloat(minY),
            width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1)
        ),
        radius
    )
}

/// Crops the artwork out of its white margin and re-rounds it, leaving transparent corners so
/// the icon sits on any page background.
func roundedIcon(from image: CGImage, size: Int) -> CGImage {
    let px = Pixels(image)
    let (box, radius) = measureArtwork(px)

    // CGImage cropping is in top-left coordinates, same as the pixel scan.
    guard let cropped = image.cropping(to: box) else { die("crop failed") }
    let scale = CGFloat(size) / max(box.width, box.height)

    let ctx = newContext(width: size, height: size)
    let square = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
    let r = radius * scale
    ctx.addPath(CGPath(roundedRect: square, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.clip()
    ctx.draw(cropped, in: square)
    guard let out = ctx.makeImage() else { die("icon render failed") }
    return out
}

// MARK: - Open Graph card

func hex(_ value: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha
    )
}

func drawText(
    _ ctx: CGContext,
    _ string: String,
    font: NSFont,
    color: CGColor,
    at origin: CGPoint,
    tracking: CGFloat = 0
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color) ?? .white,
        .kern: tracking,
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: string, attributes: attributes)
    )
    ctx.textPosition = origin
    CTLineDraw(line, ctx)
}

func makeOpenGraphCard(icon: CGImage, to path: String) {
    let width = 1200, height = 630
    let ctx = newContext(width: width, height: height)

    // Background: a deep navy that matches the icon's ground, with a soft diagonal lift.
    ctx.setFillColor(hex(0x0A1030))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    if let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [hex(0x18409E, alpha: 0.55), hex(0x0A1030, alpha: 0.0)] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 1200, y: 630),
            end: CGPoint(x: 220, y: -60),
            options: []
        )
    }

    // Icon, left-aligned.
    let iconSide: CGFloat = 260
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: hex(0x000000, alpha: 0.45))
    ctx.draw(icon, in: CGRect(x: 96, y: 185, width: iconSide, height: iconSide))
    ctx.restoreGState()

    let textX: CGFloat = 96 + iconSide + 68

    drawText(
        ctx, "AIR CONTROL",
        font: NSFont.systemFont(ofSize: 26, weight: .semibold),
        color: hex(0x7FB2FF), at: CGPoint(x: textX, y: 404), tracking: 6
    )
    drawText(
        ctx, "Your iPhone is the",
        font: NSFont.systemFont(ofSize: 62, weight: .bold),
        color: hex(0xFFFFFF), at: CGPoint(x: textX, y: 318), tracking: -1.2
    )
    drawText(
        ctx, "trackpad for your Mac.",
        font: NSFont.systemFont(ofSize: 62, weight: .bold),
        color: hex(0xFFFFFF), at: CGPoint(x: textX, y: 240), tracking: -1.2
    )
    drawText(
        ctx, "Free and open source  ·  Local Wi-Fi only  ·  No accounts",
        font: NSFont.systemFont(ofSize: 26, weight: .medium),
        color: hex(0xA8BEE6), at: CGPoint(x: textX, y: 178)
    )

    guard let out = ctx.makeImage() else { die("og render failed") }
    writePNG(out, to: path)
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count == 2 else { die("usage: make-assets <repo-root>") }
let root = arguments[1]

let iosSource = loadImage("\(root)/design/icons/ios-icon-source.png")
let macSource = loadImage("\(root)/design/icons/mac-icon-source.png")

print("Generating landing page assets…")

// The hero renders these at 168 CSS px at most, so 384 covers a 2x display with
// room to spare and keeps the page's image payload small.
let iosIcon = roundedIcon(from: iosSource, size: 384)
let macIcon = roundedIcon(from: macSource, size: 384)

writePNG(iosIcon, to: "\(root)/site/public/icon-ios.png")
writePNG(macIcon, to: "\(root)/site/public/icon-mac.png")
writePNG(roundedIcon(from: iosSource, size: 512), to: "\(root)/site/src/app/icon.png")
writePNG(roundedIcon(from: iosSource, size: 180), to: "\(root)/site/src/app/apple-icon.png")
makeOpenGraphCard(icon: roundedIcon(from: macSource, size: 512), to: "\(root)/site/public/og.png")

print("Done.")
