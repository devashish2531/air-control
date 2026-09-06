# 08 — UI revamp (iOS shell, keyboard, theming, onboarding; Mac proper app)

Status: planned 2026-09-06 by the Fable orchestrator from owner device screenshots; implemented by
parallel Sonnet 5 agents. Cite sections in code as `// docs/08 §n`. Where this document contradicts
`docs/03-specifications.md` or `docs/04-architecture.md`, this document wins (owner decision, see §6).

## 1. Problems observed (owner screenshots, iPhone 17 Pro, dark mode)

1. Two "Not connected" pills on the Touchpad tab: the toolbar pill (`RootTabView.ConnectionPillButton`)
   and the touchpad's own ribbon (`TouchpadModeRibbon`). Same information, twice.
2. Every other tab also carries the wide toolbar pill; it crowds the toolbar and collides with the
   Keyboard tab's own button group (the "hide keyboard" button overlaps the pill).
3. Keyboard tab: modifier/extended/F-key rows use a lot of vertical space; the Send button floats;
   the hide-keyboard control sits on the left, apart from the other controls; when the system
   keyboard is up the root tab bar is covered, so switching to Remote requires dismissing first.
4. No light theme; several screens hard-code near-black/black. The `Appearance` setting
   (`UserSettings.appearance`: light/dark/system) exists but is never applied.
5. Onboarding buttons collide and the onboarding does not follow the device theme.
6. Touchpad surface is a flat black; a very slight dot pattern should read as "this is the pad".
7. Mac helper is a menu-bar-only agent (LSUIElement). Owner wants a proper app: Dock icon,
   a main window with status and defined screens, plus the existing menu-bar extra.

## 2. iOS shell (owner: shell agent — `Sources/App/RootTabView.swift`, `Sources/Support/*`, `Sources/Features/Touchpad/*`, `Sources/Features/Devices/*`)

### 2.1 One connection indicator per screen
- Remove `ConnectionPillButton` and its width/offset workarounds entirely.
- Add `ConnectionStatusDot` (new file `Sources/App/ConnectionStatusDot.swift`): a 10 pt circle
  (green = connected, amber pulsing = connecting/reconnecting, grey = disconnected, red = error)
  placed as the **top-leading toolbar item on every tab**. Tap → Devices sheet. Accessibility
  label "Connected to <host>" / "Not connected"; VoiceOver value announces state changes.
  Optional short text label appears only on iPad regular width.
- Touchpad: `TouchpadModeRibbon` loses its connection text. It becomes a compact trailing
  control (44 pt circle with `slider.horizontal.3`) that opens the touchpad quick settings. If the
  ribbon carried mode text (relative/absolute etc.) keep it as a small caption inside the quick
  settings, not on the pad.
- Air Pointer tab: keep the existing "Not connected — motion won't reach your Mac" banner (it is
  actionable copy, not a duplicate pill) but reduce it to one line, secondary style.

### 2.2 Tab switching while the keyboard is up
- New environment key in `Sources/Support/TabSwitcher.swift` (written by the orchestrator):
  `@Environment(\.tabSwitcher)` → `TabSwitcher { AppTab -> Void }` plus `openSettings()`.
- `RootTabView` injects a `TabSwitcher` that sets `selectedTab` / `showSettings`.
- The Keyboard feature (§3) shows a compact tab strip in the keyboard's input accessory view and
  calls the switcher.

### 2.3 Theme application
- `RootTabView` applies `.preferredColorScheme(environment.userSettings.appearance.colorScheme)`
  (`.system` → nil). `AppearanceSetting.colorScheme` lives in `Sources/Support/Appearance.swift`.
- The onboarding cover and all sheets inherit it automatically (they are presented from the root).

### 2.4 Touchpad surface
- `TouchpadGridBackground`: dot grid, 24 pt spacing, dots 1.5 pt, colour `.primary.opacity(0.06)`
  light / `0.10` dark; pad fill `Color(.secondarySystemBackground)`; 20 pt continuous corner
  radius; 1 pt hairline border `.separator`. Reads as a surface in both themes.
- Click buttons: `Color(.tertiarySystemBackground)`, pressed state `.quaternaryLabel`. Labels
  "Left click"/"Right click" hidden after first successful click (persist a `hasUsedClickButtons`
  flag in `UserSettings`), replaced by nothing (clean pads).
- Keep 64 pt bottom buttons, 48 pt right scroll strip, DEBUG label only in `#if DEBUG`.

## 3. Keyboard tab (owner: keyboard agent — `Sources/Features/Keyboard/*`, `Sources/Services/KeyboardBridge/KeyInputHostView.swift`, `KeyInputHostRepresentable.swift`)

### 3.1 Layout
- Toolbar (trailing group only, 44 pt items): Show/Hide keyboard (`keyboard` / `keyboard.chevron.compact.down`),
  Secure entry toggle (eye), Return. Remove the leading floating hide button. Gear stays as the
  shell's item; do not add a second gear.
- Screen order top→bottom: Live/Commit segmented control · (Commit mode) text area with Send in
  the field's trailing edge · modifier row · **one horizontally scrolling `ExtendedKeyBar`** with
  sections Esc/Tab/Return/⌫/⌦ · arrows · Home/End/PgUp/PgDn · F1–F12 (section headers as tiny
  captions; snap by section) · Media row · Shortcuts.
- When the system keyboard is visible, collapse to: segmented control · modifier row · extended
  bar. Everything else scrolls under the keyboard; never let content sit under the keyboard.
- Keys: 44 pt tall, 8 pt spacing, `RoundedRectangle(cornerRadius: 10, style: .continuous)`,
  fill `Color(.secondarySystemBackground)`, pressed `.tertiarySystemBackground`, latched
  modifiers `.tint.opacity(0.2)` fill with `.tint` glyph. Same in light and dark.

### 3.2 Input accessory tab strip
- `KeyInputHostView.inputAccessoryView` becomes a `UIInputView` hosting a SwiftUI
  `KeyboardAccessoryBar`: five tab icons (from `AppTab.systemImage`, current tab highlighted),
  a gear, and a trailing "Done" (hide keyboard). Height 44 pt, material background.
- Tapping a tab calls `tabSwitcher.switchTo(tab)` (§2.2) and resigns first responder.
- The bar is provided by the SwiftUI side via `KeyInputHostRepresentable` (a closure/binding);
  the UIKit class stays free of SwiftUI imports except for `UIHostingController`.

## 4. Theme + onboarding + secondary screens (owner: theme agent — `Sources/Features/Onboarding/*`, `Sources/Features/Settings/*`, `Sources/Features/Remote/*`, `Sources/Features/AirPointer/*`, `Sources/Features/Macros/*`, `Sources/Features/Diagnostics/*`, `Sources/Features/Pairing/*`, `Sources/Support/Appearance.swift`)

- Write `Sources/Support/Appearance.swift`: `extension AppearanceSetting { var colorScheme: ColorScheme? }`.
- Settings: ensure the Appearance picker (System/Light/Dark) is in the first "Appearance" section
  and takes effect immediately (it is `@Observable`; verify the binding writes through).
- Audit every file in scope: replace `Color.black`, `.white`, `Color(white:)`, fixed hex, and
  `.opacity` on black with semantic colours (`Color(.systemBackground)`, `.secondarySystemBackground`,
  `.label`, `.secondaryLabel`, `.separator`, `.tint`). Screens must look correct in both themes;
  verify by running each screen in the simulator with `-AppleInterfaceStyle Light` and Dark.
- Onboarding: buttons must not overlap. Use a single bottom `VStack(spacing: 12)` inside
  `safeAreaInset(edge: .bottom)` with a `.borderedProminent` primary and `.bordered` secondary,
  both `frame(maxWidth: .infinity)`, 50 pt tall; page content in a `ScrollView` above. Test on
  iPhone SE (3rd gen) and iPhone 17 Pro in the simulator. Follows the device/app theme (no
  forced `.dark`).
- Remote tab: "No Mac connected" title → keep, but as `.secondary` caption; the big Previous/Next
  and round buttons adopt the §3.1 key style so the app looks like one product.

## 5. Mac app: from menu-bar agent to proper app (owner: Mac agent — all of `apps/AirControl-Mac/**`)

### 5.1 App shell
- `LSUIElement` → `NO`. Dock icon shows the existing `AppIcon`. `CFBundleDisplayName` = "Air Control"
  (bundle id unchanged, so the Accessibility grant survives).
- Keep the `MenuBarExtra` (status glyph + quick menu: status line, Pair New Device…, Open Air
  Control, Preferences…, Quit).
- Add a setting "Show in Dock" (default on). Off → `NSApp.setActivationPolicy(.accessory)` at
  launch and the menu bar item is the only entry point; on → `.regular`.
- Main window `Window("Air Control", id: WindowID.main)`, min 820×560, remembers frame.
  Closing it does not quit (`applicationShouldTerminateAfterLastWindowClosed = false`); Cmd-Q quits.
  Launching the app while running re-opens/raises the main window. First launch after onboarding
  opens the main window.

### 5.2 Main window = `NavigationSplitView` with sidebar
Sidebar items (SF Symbols in parentheses), each a screen in `Sources/Features/MainWindow/`:
1. **Overview** (`gauge.with.dots.needle.33percent`): status card — server Running/Stopped with
   TCP/UDP ports, Accessibility permission state with "Open System Settings" button, Local Network
   note, currently connected device (name, transport UDP/TCP fallback, RTT, since) or "No device
   connected"; primary button **Pair New Device** shows the QR inline in the card (reuse
   `PairingContentView`), secondary **Copy pairing link**. A "Recent activity" list reuses the
   Diagnostics ring buffer (last 10).
2. **Devices** (`iphone.and.arrow.forward`): reuse `TrustedDevicesWindow` content — list, last
   seen, revoke/forget, rename.
3. **Macros** (`square.grid.2x2`): embed the existing macro editor.
4. **Diagnostics** (`waveform.path.ecg`): embed the existing diagnostics view.
5. **Settings** (`gearshape`): embed the existing preferences tabs as a segmented/tabbed detail.
- Remove the separate `Window`s for pairing/trusted devices/diagnostics/macros; the menu bar
  items deep-link into the main window (`openWindow(id: .main)` + selected sidebar item via an
  `@Observable MainWindowRouter` in `Sources/App/`). Keep the Onboarding window; it ends by
  opening the main window. Keep `Settings` scene for Cmd-, mapping to the Settings sidebar item.
- Sidebar shows a live status dot next to "Overview" (same colours as iOS §2.1).
- Follows system appearance (no forced scheme); test light and dark.

### 5.3 Non-goals
- No Sparkle, no new features, no protocol changes. `--loopback`, `--print-pair-url`,
  `--show-onboarding` keep working (CI and the loopback UI tests depend on them).

## 6. Deviations from earlier docs (recorded here, not edited in `docs/0*.md`)
- spec §5.1.1 "LSUIElement = YES agent app; no Dock icon" → superseded by §5.1 (owner request 2026-09-06).
- spec §4.1 toolbar "connection pill" → superseded by §2.1 status dot.
- Public name "Air Control" now used as the Mac display name; iOS display name rename pending.

## 7. Acceptance checklist (owner test on device / Mac)
- [ ] Exactly one connection indicator per iOS screen; toolbar never overflows on iPhone.
- [ ] Keyboard: hide/show sits with the other trailing controls; accessory bar above the system
      keyboard switches tabs without dismissing first.
- [ ] Settings → Appearance switches the whole app immediately; every screen readable in Light.
- [ ] Onboarding: no overlapping buttons on iPhone SE and iPhone 17 Pro; follows theme.
- [ ] Touchpad shows a subtle dot surface in both themes.
- [ ] Mac: Dock icon, main window with the five sidebar screens, status and QR on Overview,
      menu-bar extra still present, Accessibility grant preserved after `make mac-run`.
- [ ] `make kit-test`, `make ios-test`, `make mac-build` green; CI warnings-as-errors green.
