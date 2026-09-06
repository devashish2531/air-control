// make-assets.swift — regenerates the landing page's static images.
//
// Inputs : design/icons/{ios,mac}-icon-source.png — 1024x1024 full-bleed artwork,
//          drawn by scripts/icon-tools/IconDraw.swift (see design/icons/README.md).
//          Neither source carries a corner radius, so this file applies the shape
//          each platform would apply itself.
// Outputs: site/public/icon-ios.png          iOS squircle, 384 (bright)
//          site/public/icon-mac.png          macOS body shape + shadow, 384 (dark)
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
import SwiftUI

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

/// Apple's continuous ("squircle") rounded rectangle — the shape both platforms use.
func squirclePath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    SwiftUI.Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath
}

/// The iOS home-screen shape: the full-bleed artwork masked by the system
/// squircle. Radius 0.2237 x side is the iOS app-icon proportion.
func iosIcon(from image: CGImage, size: Int) -> CGImage {
    let side = CGFloat(size)
    let square = CGRect(x: 0, y: 0, width: side, height: side)
    let ctx = newContext(width: size, height: size)
    ctx.addPath(squirclePath(square, radius: side * 0.2237))
    ctx.clip()
    ctx.draw(image, in: square)
    guard let out = ctx.makeImage() else { die("iOS icon render failed") }
    return out
}

/// The macOS 11+ icon shape: an 824/1024 body inside a transparent canvas, with
/// the same continuous radius and drop shadows as scripts/icon-tools/IconTool.swift.
func macIcon(from image: CGImage, size: Int) -> CGImage {
    let scale = CGFloat(size) / 1024
    let body = 824 * scale
    let origin = (CGFloat(size) - body) / 2
    let rect = CGRect(x: origin, y: origin, width: body, height: body)
    let path = squirclePath(rect, radius: 215 * scale)

    let ctx = newContext(width: size, height: size)
    for (offsetY, blur, alpha) in [(-14.0, 30.0, 0.16), (-5.0, 10.0, 0.14)] {
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: offsetY * scale), blur: blur * scale,
            color: hex(0x000000, alpha: alpha)
        )
        ctx.setFillColor(hex(0x000000))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(image, in: rect)
    ctx.restoreGState()

    guard let out = ctx.makeImage() else { die("macOS icon render failed") }
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
writePNG(iosIcon(from: iosSource, size: 384), to: "\(root)/site/public/icon-ios.png")
writePNG(macIcon(from: macSource, size: 384), to: "\(root)/site/public/icon-mac.png")
writePNG(iosIcon(from: iosSource, size: 512), to: "\(root)/site/src/app/icon.png")
writePNG(iosIcon(from: iosSource, size: 180), to: "\(root)/site/src/app/apple-icon.png")
// The card's ground is navy, so the bright iOS icon carries it; the navy macOS
// body would disappear into the background.
makeOpenGraphCard(icon: iosIcon(from: iosSource, size: 512), to: "\(root)/site/public/og.png")

print("Done.")
