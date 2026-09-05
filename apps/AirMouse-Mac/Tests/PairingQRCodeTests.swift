// PairingQRCodeTests — spec §3.1.3 (QR payload/error correction/quiet zone), and the Onboarding "Pair"
// step review: the QR bitmap must be an opaque, crisp black-on-white code (never a blank/transparent
// square) in both light and dark mode, since it's rendered directly over whatever's behind it.
@testable import Air_Mouse
import AppKit
import Testing

@Suite("PairingQRCode")
struct PairingQRCodeTests {
    private static let samplePairingURL =
        "airmouse://pair?host=Devashishs-Mac&secret=ABCDEF0123456789&port=47800&fp=deadbeef"

    @Test("renders a non-nil image at the requested pixel size for a sample pairing URL")
    func rendersNonNilAtExpectedSize() throws {
        let image = try #require(PairingQRCode.image(for: Self.samplePairingURL))
        #expect(image.size == NSSize(width: 300, height: 300))

        let rep = try #require(bitmap(for: image))
        // The bitmap's pixel dimensions should match the requested point size (no surprise
        // downscaling that would blur the modules below scannability).
        #expect(rep.pixelsWide >= 300)
        #expect(rep.pixelsHigh >= 300)
    }

    @Test("contains both dark (module) and light (background/quiet-zone) pixels")
    func containsDarkAndLightPixels() throws {
        let image = try #require(PairingQRCode.image(for: Self.samplePairingURL))
        let rep = try #require(bitmap(for: image))

        var darkCount = 0
        var lightCount = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                if color.redComponent < 0.2 {
                    darkCount += 1
                } else if color.redComponent > 0.8 {
                    lightCount += 1
                }
            }
        }
        #expect(darkCount > 0, "expected at least one dark QR-module pixel")
        #expect(lightCount > 0, "expected at least one light background pixel")
    }

    @Test("the quiet-zone border is opaque white, not transparent, regardless of appearance")
    func quietZoneIsOpaqueWhite() throws {
        let image = try #require(PairingQRCode.image(for: Self.samplePairingURL))
        let rep = try #require(bitmap(for: image))

        // A couple of points into the border (inside the 4-module quiet zone, spec §3.1.3) —
        // must be fully opaque white so a dark window/background never shows through.
        let corner = try #require(rep.colorAt(x: 2, y: 2))
        #expect(corner.alphaComponent == 1)
        #expect(corner.redComponent > 0.95)
        #expect(corner.greenComponent > 0.95)
        #expect(corner.blueComponent > 0.95)
    }

    @Test("honors a custom targetSize")
    func honorsCustomTargetSize() throws {
        let image = try #require(PairingQRCode.image(for: Self.samplePairingURL, targetSize: 150))
        #expect(image.size == NSSize(width: 150, height: 150))
    }

    private func bitmap(for image: NSImage) -> NSBitmapImageRep? {
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }
}
