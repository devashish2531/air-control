// IconDraw.swift — draws the Air Mouse app-icon artwork as vector shapes.
//
// This is the *source of truth* for the icon artwork. It renders 1024x1024
// full-bleed opaque PNGs into design/icons, which `IconTool.swift` then turns
// into the platform icon sets (see design/icons/README.md). Nothing here crops
// or traces a bitmap: every shape is a CoreGraphics path.
//
// Design brief (2026-09-06, owner reference design/icons/reference-2026-09-06.png):
//   * Same two compositions as the reference, but flat and geometric —
//     no gloss, no wavy overlays, no blur, no glow.
//   * Background: one two-stop linear gradient, bottom-left -> top-right.
//   * Consistent stroke widths, round caps, generous margins: the artwork sits
//     inside ~80% of the canvas (Apple HIG).
//   * No corner rounding is baked in. iOS masks its icon; the macOS body shape
//     (824/1024 rounded square + shadow) is applied later by IconTool.
//
// Usage:
//   IconDraw ios      <out.png>     bright royal-blue -> cyan, Wi-Fi over a mouse
//   IconDraw ios-dark <out.png>     the same composition on the deep navy ground
//   IconDraw mac      <out.png>     deep navy, laptop with Wi-Fi on screen + mouse
//   IconDraw preview  <ref.png> <ios.png> <mac.png> <out.png>
//
// Build:  swiftc -O -o icondraw IconDraw.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Infrastructure

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("IconDraw: \(message)\n".utf8))
    exit(1)
}

let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha
    )
}

/// A context whose user space is top-left origin, y growing downward, so the
/// layout numbers below read the way a designer would write them.
func flippedContext(width: Int, height: Int, opaque: Bool) -> CGContext {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: rgb, bitmapInfo: info.rawValue
    ) else { die("cannot create a \(width)x\(height) context") }
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    return ctx
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { die("cannot open \(path) for writing") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { die("cannot write \(path)") }
    print("  wrote \(path) — \(image.width)x\(image.height)")
}

/// Draw a bitmap the right way up inside a flipped (y-down) context.
func drawImage(_ ctx: CGContext, _ image: CGImage, in rect: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    ctx.restoreGState()
}

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { die("cannot read \(path)") }
    return image
}

// MARK: - Shape helpers

/// A stadium/rounded-rect path. `radius` is clamped to half the shorter side.
func capsulePath(x: Double, y: Double, width: Double, height: Double, radius: Double) -> CGPath {
    let r = min(radius, min(width, height) / 2)
    return CGPath(
        roundedRect: CGRect(x: x, y: y, width: width, height: height),
        cornerWidth: r, cornerHeight: r, transform: nil
    )
}

/// One Wi-Fi arc: a stroked circular arc centred on `center`, opening upward,
/// spanning +/- `halfSpan` degrees about vertical, with round caps.
func wifiArcPath(center: CGPoint, radius: Double, halfSpan: Double) -> CGPath {
    let up = -Double.pi / 2
    let span = halfSpan * Double.pi / 180
    let path = CGMutablePath()
    path.addArc(
        center: center, radius: radius,
        startAngle: up - span, endAngle: up + span,
        clockwise: false
    )
    return path
}

/// The three-arc Wi-Fi glyph. Arcs are evenly spaced so the gaps between the
/// strokes are identical — the whole point of drawing this rather than tracing it.
func drawWiFi(
    _ ctx: CGContext, center: CGPoint, radii: [Double], stroke: Double,
    halfSpan: Double, color: CGColor
) {
    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    for radius in radii {
        ctx.addPath(wifiArcPath(center: center, radius: radius, halfSpan: halfSpan))
        ctx.strokePath()
    }
    ctx.restoreGState()
}

/// Background: a single two-stop linear gradient, bottom-left -> top-right.
func drawBackground(_ ctx: CGContext, side: Double, from: CGColor, to: CGColor) {
    guard let gradient = CGGradient(
        colorsSpace: rgb, colors: [from, to] as CFArray, locations: [0, 1]
    ) else { die("cannot build the background gradient") }
    ctx.saveGState()
    ctx.addRect(CGRect(x: 0, y: 0, width: side, height: side))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        // Pulled a little inside the corners so each end tone owns a real area
        // of the icon instead of only its corner pixel — flat, not washed out.
        start: CGPoint(x: side * 0.10, y: side * 0.90),  // bottom-left (flipped space)
        end: CGPoint(x: side * 0.92, y: side * 0.08),    // top-right
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

// MARK: - Palette

enum Palette {
    /// iOS light: bright royal blue -> cyan.
    static let iosFrom = hex(0x0733CC)
    static let iosTo = hex(0x23D6FF)
    /// The scroll slot punched into the white mouse on the bright ground.
    static let iosSlot = hex(0x0B44DC)

    /// macOS / iOS dark: deep navy -> a restrained blue lift.
    static let navyFrom = hex(0x071026)
    static let navyTo = hex(0x1650BE)
    static let navySlot = hex(0x0E2A5E)

    static let white = hex(0xFFFFFF)
}

let canvas = 1024.0

// MARK: - iOS composition
//
// Content box: x 194..830, y 102..922 — 80% of the canvas tall, centred.
// The Wi-Fi arcs are concentric on (512, 505); the smallest arc's round caps
// stop 23 px above the mouse.

enum IOSLayout {
    static let wifiCenter = CGPoint(x: 512, y: 505)
    static let wifiRadii = [170.0, 270.0, 370.0]
    static let wifiStroke = 66.0
    static let wifiHalfSpan = 50.0

    static let mouseWidth = 360.0
    static let mouseHeight = 470.0
    static let mouseTop = 452.0

    static let slotWidth = 30.0
    static let slotHeight = 140.0
    static let slotInset = 46.0 // below the mouse's top edge
}

func drawIOSArtwork(_ ctx: CGContext, from: CGColor, to: CGColor, slot: CGColor) {
    drawBackground(ctx, side: canvas, from: from, to: to)

    drawWiFi(
        ctx, center: IOSLayout.wifiCenter, radii: IOSLayout.wifiRadii,
        stroke: IOSLayout.wifiStroke, halfSpan: IOSLayout.wifiHalfSpan, color: Palette.white
    )

    let mouse = capsulePath(
        x: 512 - IOSLayout.mouseWidth / 2, y: IOSLayout.mouseTop,
        width: IOSLayout.mouseWidth, height: IOSLayout.mouseHeight,
        radius: IOSLayout.mouseWidth / 2
    )
    ctx.setFillColor(Palette.white)
    ctx.addPath(mouse)
    ctx.fillPath()

    ctx.setFillColor(slot)
    ctx.addPath(capsulePath(
        x: 512 - IOSLayout.slotWidth / 2,
        y: IOSLayout.mouseTop + IOSLayout.slotInset,
        width: IOSLayout.slotWidth, height: IOSLayout.slotHeight,
        radius: IOSLayout.slotWidth / 2
    ))
    ctx.fillPath()
}

// MARK: - macOS composition
//
// Content box: x 102..922, y 150..874. The base bar is the widest element at
// 80% of the canvas; everything is centred on x = 512.
//
// Vertical stack: screen 150..546, 18 px gap, base bar 564..602, and the mouse
// hanging from the bar top down to 874. The mouse is drawn last with a
// background-coloured knockout so it reads as being in front of the bar.

enum MacLayout {
    static let screenOuter = CGRect(x: 167, y: 150, width: 690, height: 396)
    static let screenStroke = 30.0
    static let screenRadius = 40.0 // outer radius

    static let barRect = CGRect(x: 102, y: 564, width: 820, height: 38)

    static let mouseWidth = 222.0
    static let mouseHeight = 310.0
    static let mouseTop = 564.0
    static let knockout = 11.0 // navy gap drawn around the mouse

    static let slotWidth = 20.0
    static let slotHeight = 92.0
    static let slotInset = 30.0

    static let wifiCenter = CGPoint(x: 512, y: 514)
    static let wifiRadii = [112.0, 178.0, 244.0]
    static let wifiStroke = 44.0
    static let wifiHalfSpan = 50.0
}

func drawMacArtwork(_ ctx: CGContext) {
    drawBackground(ctx, side: canvas, from: Palette.navyFrom, to: Palette.navyTo)

    let mouseRect = CGRect(
        x: 512 - MacLayout.mouseWidth / 2, y: MacLayout.mouseTop,
        width: MacLayout.mouseWidth, height: MacLayout.mouseHeight
    )
    let mouse = capsulePath(
        x: mouseRect.minX, y: mouseRect.minY,
        width: mouseRect.width, height: mouseRect.height,
        radius: MacLayout.mouseWidth / 2
    )
    let halo = capsulePath(
        x: mouseRect.minX - MacLayout.knockout, y: mouseRect.minY - MacLayout.knockout,
        width: mouseRect.width + 2 * MacLayout.knockout,
        height: mouseRect.height + 2 * MacLayout.knockout,
        radius: MacLayout.mouseWidth / 2 + MacLayout.knockout
    )

    // Everything behind the mouse is clipped to the canvas minus that halo, so
    // the white bar never merges into the white mouse.
    ctx.saveGState()
    ctx.addRect(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    ctx.addPath(halo)
    ctx.clip(using: .evenOdd)

    // Screen: an even-weight rounded-rect outline. The stroke is centred on the
    // path, so the path rect is the outer rect inset by half the stroke.
    let half = MacLayout.screenStroke / 2
    ctx.setStrokeColor(Palette.white)
    ctx.setLineWidth(MacLayout.screenStroke)
    ctx.setLineJoin(.round)
    ctx.addPath(capsulePath(
        x: MacLayout.screenOuter.minX + half, y: MacLayout.screenOuter.minY + half,
        width: MacLayout.screenOuter.width - MacLayout.screenStroke,
        height: MacLayout.screenOuter.height - MacLayout.screenStroke,
        radius: MacLayout.screenRadius - half
    ))
    ctx.strokePath()

    drawWiFi(
        ctx, center: MacLayout.wifiCenter, radii: MacLayout.wifiRadii,
        stroke: MacLayout.wifiStroke, halfSpan: MacLayout.wifiHalfSpan, color: Palette.white
    )

    ctx.setFillColor(Palette.white)
    ctx.addPath(capsulePath(
        x: MacLayout.barRect.minX, y: MacLayout.barRect.minY,
        width: MacLayout.barRect.width, height: MacLayout.barRect.height,
        radius: MacLayout.barRect.height / 2
    ))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.setFillColor(Palette.white)
    ctx.addPath(mouse)
    ctx.fillPath()

    ctx.setFillColor(Palette.navySlot)
    ctx.addPath(capsulePath(
        x: 512 - MacLayout.slotWidth / 2, y: MacLayout.mouseTop + MacLayout.slotInset,
        width: MacLayout.slotWidth, height: MacLayout.slotHeight,
        radius: MacLayout.slotWidth / 2
    ))
    ctx.fillPath()
}

// MARK: - Renderers

func render(_ body: (CGContext) -> Void) -> CGImage {
    let ctx = flippedContext(width: Int(canvas), height: Int(canvas), opaque: true)
    body(ctx)
    guard let image = ctx.makeImage() else { die("render failed") }
    return image
}

// MARK: - Preview sheet

/// Side-by-side contact sheet: the owner's reference on top, the new renders
/// below, both masked the way each platform will show them.
func makePreview(reference: String, ios: String, mac: String, output: String) {
    let referenceImage = loadImage(reference)
    let iosImage = loadImage(ios)
    let macImage = loadImage(mac)

    let width = 1600
    let margin = 60.0
    let tile = (Double(width) - 3 * margin) / 2
    let referenceHeight = Double(referenceImage.height) * (Double(width) - 2 * margin)
        / Double(referenceImage.width)
    let height = Int(margin + referenceHeight + margin + tile + margin)

    let ctx = flippedContext(width: width, height: height, opaque: true)
    ctx.setFillColor(hex(0xF2F3F5))
    ctx.fill(CGRect(x: 0, y: 0, width: Double(width), height: Double(height)))

    drawImage(ctx, referenceImage, in: CGRect(
        x: margin, y: margin, width: Double(width) - 2 * margin, height: referenceHeight
    ))

    let row = margin + referenceHeight + margin

    // iOS, masked with the system squircle so it reads as an installed icon.
    ctx.saveGState()
    ctx.addPath(CGPath(
        roundedRect: CGRect(x: margin, y: row, width: tile, height: tile),
        cornerWidth: tile * 0.2237, cornerHeight: tile * 0.2237, transform: nil
    ))
    ctx.clip()
    drawImage(ctx, iosImage, in: CGRect(x: margin, y: row, width: tile, height: tile))
    ctx.restoreGState()

    // macOS master already carries its own body shape and transparent padding.
    drawImage(ctx, macImage, in: CGRect(x: margin * 2 + tile, y: row, width: tile, height: tile))

    guard let image = ctx.makeImage() else { die("preview render failed") }
    writePNG(image, to: output)
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    die("""
    usage:
      IconDraw ios|ios-dark|mac <out.png>
      IconDraw preview <reference.png> <ios.png> <mac.png> <out.png>
    """)
}

switch command {
case "ios":
    guard arguments.count == 2 else { die("usage: IconDraw ios <out.png>") }
    writePNG(render {
        drawIOSArtwork($0, from: Palette.iosFrom, to: Palette.iosTo, slot: Palette.iosSlot)
    }, to: arguments[1])
case "ios-dark":
    guard arguments.count == 2 else { die("usage: IconDraw ios-dark <out.png>") }
    writePNG(render {
        drawIOSArtwork($0, from: Palette.navyFrom, to: Palette.navyTo, slot: Palette.navySlot)
    }, to: arguments[1])
case "mac":
    guard arguments.count == 2 else { die("usage: IconDraw mac <out.png>") }
    writePNG(render(drawMacArtwork), to: arguments[1])
case "preview":
    guard arguments.count == 5 else {
        die("usage: IconDraw preview <reference.png> <ios.png> <mac.png> <out.png>")
    }
    makePreview(
        reference: arguments[1], ios: arguments[2], mac: arguments[3], output: arguments[4]
    )
default:
    die("unknown command \(command)")
}
