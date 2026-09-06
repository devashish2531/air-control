# App icons

Everything Xcode ships as an app icon is generated, and so is the artwork itself.
Nothing in either `AppIcon.appiconset` is hand-edited, and neither is any
`*-icon-source.png` in this directory — treat all of it as build output.

```sh
./scripts/gen-icons.sh
```

## The two tools

| File | Role |
| --- | --- |
| `scripts/icon-tools/IconDraw.swift` | draws the artwork as CoreGraphics vector shapes → the three source PNGs |
| `scripts/icon-tools/IconTool.swift` | turns a source PNG into the platform icon files |

`gen-icons.sh` compiles both with `swiftc -O` into a temporary directory and runs
them in that order. Requires Xcode (`DEVELOPER_DIR`, default
`/Applications/Xcode.app/Contents/Developer`); no Homebrew, no ImageMagick, no
image editor.

## Sources (generated)

| File | Size | Alpha | Drawn by | Used for |
| --- | --- | --- | --- | --- |
| `ios-icon-source.png` | 1024×1024 | no | `IconDraw ios` | iOS light appearance |
| `ios-icon-source-dark.png` | 1024×1024 | no | `IconDraw ios-dark` | iOS dark + tinted appearances |
| `mac-icon-source.png` | 1024×1024 | no | `IconDraw mac` | the macOS icon |

All three are **full-bleed**: edge-to-edge artwork, opaque, with **no corner
radius and no margin baked in**. Corner shape is a platform concern and is
applied downstream, never here.

## The artwork

Two compositions, from the owner's reference `reference-2026-09-06.png`:

* **iOS** — three Wi-Fi arcs above a capsule mouse with a scroll slot, on a
  bright royal-blue → cyan ground.
* **macOS** — a laptop drawn as a rounded-rect screen outline plus a capsule
  base bar, Wi-Fi arcs on the screen, and the same mouse hanging in front of the
  base bar, on a deep navy ground.

Flat by rule: one two-stop linear gradient per background (bottom-left →
top-right, its ends pulled 10% inside the corners so each tone owns real area),
pure white shapes, no gloss, no overlay waves, no blur, no glow. Every arc is a
stroked circular arc with round caps sharing one centre and one stroke width, so
the gaps between arcs are exactly equal; the mouse and the base bar are
rounded rects with a radius of half the short side. Content sits inside ~80% of
the canvas (Apple HIG) and is centred on x = 512. On the macOS icon the mouse is
drawn last over a background-coloured knockout, so the white mouse never merges
into the white base bar. All the numbers live in the `IOSLayout` / `MacLayout`
enums in `IconDraw.swift` — change them there, never in a bitmap.

`IconDraw preview <reference.png> <ios.png> <mac.png> <out.png>` renders the
side-by-side contact sheet used to review a change against the reference;
`preview-2026-09-06.png` is the one for this design.

## The mask rules

`IconTool` still contains an `expandToEdges` pass that repaints a white or
transparent exterior outward from the artwork's boundary. With the code-drawn
sources there is no exterior to find, so it is a no-op — it is kept because it is
what makes the tool safe to point at a hand-supplied bitmap.

**iOS** — the source is passed through with `--inset 0` (nothing to crop: the
artwork already reaches every edge) and written as 1024×1024 sRGB with **no alpha
channel**; the App Store rejects icons that have one. The icon is full-bleed: iOS
applies its own mask, so the blue reaches every edge and corner and nothing can
peek out from under the system's squircle. Xcode 26 needs only this single
universal 1024 entry. Two more are supplied as iOS 18+ appearances — `dark` (the
same composition on the navy ground) and `tinted` (a Rec. 709 luminance
grayscale of that navy artwork, whose darker ground gives the system tint more
contrast than the bright blue one would). `actool` accepts all three; they land
in `Assets.car` as `UIAppearanceDark` and `ISAppearanceTintable` renditions.

**macOS** — macOS does *not* mask, so the shape is baked in here: the square is
drawn into the system icon body on a transparent 1024×1024 canvas, **824×824
centred** (100 px margin on every side — the ~10% transparent padding macOS 11+
icons carry), clipped to a **continuous ("squircle") rounded rectangle of radius
215**, with two soft black drop shadows (offset 14 px / blur 30 / 16% and offset
5 px / blur 10 / 14%). That geometry is not a guess — it was calibrated by
rendering Notes, Maps, Music and Xcode through `NSWorkspace.icon(forFile:)` at
1024 and fitting their alpha profile. All four are byte-identical in shape, and
`cornerRadius: 215, style: .continuous` reproduces it to an RMS of 0.6 px (a
circular corner cannot: the real shape's diagonal cut is 63 px where a circle of
the same edge span would cut 111 px). Note this is the macOS 26 shape, which is
rounder than the pre-Tahoe template. The ten declared sizes are then produced by
repeated halving from the 1024 master with high-quality interpolation, so 16 and
32 stay crisp instead of aliasing.

`gen-icons.sh` finishes by checking that the iOS icon has no alpha channel and
that the macOS set survives an `iconutil -c icns` round trip.

## The landing page

`site/scripts/make-assets.sh` reads the same two sources and applies the same
two shapes — the iOS squircle for `site/public/icon-ios.png`, the favicon, the
touch icon and the Open Graph card; the macOS body shape and shadow for
`site/public/icon-mac.png`. Run it after `gen-icons.sh` whenever the artwork
changes. It never touches the site's SVG logo components.

## Wiring

Both app targets compile `Resources/Assets.xcassets`, but `actool` only designates
an app icon when `ASSETCATALOG_COMPILER_APPICON_NAME` is set. Without it no
`Assets.car` is emitted and no `CFBundleIconName` reaches `Info.plist`, so the
apps show the generic placeholder however good the assets are. That setting
belongs in `apps/*/project.yml` (or `Config/Base.xcconfig`), not here.

## Attribution

The artwork is drawn by this repository's own `IconDraw.swift` and carries the
project's licence. `reference-2026-09-06.png` is the owner's design reference and
is not shipped in either app.
