# App icons

Everything Xcode ships as an app icon is generated from the two source images in
this directory. Nothing in either `AppIcon.appiconset` is hand-edited — treat both
sets, including their `Contents.json`, as build output.

## Sources

| File | Size | Alpha | Used for |
| --- | --- | --- | --- |
| `ios-icon-source.png` | 1254×1254 | yes (opaque white corners) | iOS light appearance |
| `mac-icon-source.png` | 1254×1254 | no (white corners baked in) | macOS icon, iOS dark + tinted appearances |

Both are the same artwork — a MacBook, a Wi-Fi glyph and a mouse — drawn on a
rounded square that already has its own corner radius, on a white ground. The
generator never modifies them.

## Regenerating

```sh
./scripts/gen-icons.sh
```

It is idempotent: it deletes the generated PNGs and `Contents.json` in both
appiconsets and rewrites them from the sources, then checks that the iOS icon has
no alpha channel and that the macOS set survives an `iconutil -c icns` round trip.
Requires Xcode (`DEVELOPER_DIR`, default `/Applications/Xcode.app/Contents/Developer`);
no Homebrew or ImageMagick. The image work lives in `scripts/icon-tools/IconTool.swift`,
which `gen-icons.sh` compiles with `swiftc -O` into a temporary directory.

## The crop / mask rules

Both platforms start from the same step, because both sources carry a rounded
shape that must not survive into the output.

**Expand to edges.** The exterior background is found by flood-filling
near-white-or-transparent pixels inward from the image border, then grown two
pixels further so the anti-aliased rim of the source's own corner goes with it.
That region is repainted by growing the artwork outward from its boundary, one BFS
level at a time, averaging already-known neighbours — a smooth clamp-extension of
the background gradient into the corners. A flood fill rather than a per-pixel
colour test is essential: the artwork has a **white mouse dead centre**, and a
naive "replace the white" pass would erase it.

The result is a fully opaque square with the artwork's composition intact and no
shape of its own, which each platform then treats differently.

**iOS** — the square is centre-cropped with a 2% inset (just enough to drop the
outermost anti-aliased row) and resized to 1024×1024 sRGB with **no alpha channel**;
the App Store rejects icons that have one. The icon is full-bleed: iOS applies its
own mask, so the blue reaches every edge and corner and nothing white can peek
out from under the system's squircle. Xcode 26 needs only this single universal
1024 entry. Two more are supplied as iOS 18+ appearances — `dark` (the navy
artwork) and `tinted` (a Rec. 709 luminance grayscale of the navy artwork, whose
darker ground gives the system tint more contrast than the bright blue one would).
`actool` accepts all three; they land in `Assets.car` as `UIAppearanceDark` and
`ISAppearanceTintable` renditions.

**macOS** — the square is drawn into the system icon body on a transparent
1024×1024 canvas: **824×824 centred** (100 px margin on every side), clipped to a
**continuous ("squircle") rounded rectangle of radius 215**, with two soft black
drop shadows (offset 14 px / blur 30 / 16% and offset 5 px / blur 10 / 14%).
That geometry is not a guess — it was calibrated by rendering Notes, Maps, Music
and Xcode through `NSWorkspace.icon(forFile:)` at 1024 and fitting their alpha
profile. All four are byte-identical in shape, and `cornerRadius: 215, style: .continuous`
reproduces it to an RMS of 0.6 px (a circular corner cannot: the real shape's
diagonal cut is 63 px where a circle of the same edge span would cut 111 px).
Note this is the macOS 26 shape, which is rounder than the pre-Tahoe template.
The ten declared sizes are then produced by repeated halving from the 1024 master
with high-quality interpolation, so 16 and 32 stay crisp instead of aliasing.

## Wiring

Both app targets compile `Resources/Assets.xcassets`, but `actool` only designates
an app icon when `ASSETCATALOG_COMPILER_APPICON_NAME` is set. Without it no
`Assets.car` is emitted and no `CFBundleIconName` reaches `Info.plist`, so the
apps show the generic placeholder however good the assets are. That setting
belongs in `apps/*/project.yml` (or `Config/Base.xcconfig`), not here.

## Attribution

TODO: record the artwork's origin and licence here (author / tool / commission,
and the licence the project holds it under) before the first public release.
