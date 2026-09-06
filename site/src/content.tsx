import type { ReactNode } from "react";

import { site } from "@/site.config";

/* -------------------------------------------------------------------------- */
/* Features — one sentence each, drawn from docs/01-requirements.md §3.        */
/* -------------------------------------------------------------------------- */

/** One of the six card-strip color surfaces defined in globals.css (`--card-*`). */
export type FeatureCardTone = "blue" | "peach" | "violet" | "black" | "mint" | "gray";

export type Feature = {
  id: string;
  title: string;
  /** Punchy landing-page headline, <=6 words. Shown instead of `body`. */
  headline: string;
  /** One factual sentence, <=22 words, distilled from `body`. Shown instead of `body`. */
  benefit: string;
  /** Full sentence, kept for reference/attributes — not rendered on the page. */
  body: string;
  /** Decorative: the card header already names the feature. */
  icon: ReactNode;
  /**
   * Line-art shown filling the middle of the card
   * (`.strip-card__illustration`, `flex: 1`), aria-hidden by the caller.
   * Recolored per card via the `--ill-a`/`--ill-b` custom properties set in
   * sections.css.
   */
  illustration?: ReactNode;
  /** Which `--card-*` gradient/surface this feature's strip card uses. */
  card: FeatureCardTone;
  /** Compatibility footer value, e.g. "iPhone, iPad" (spec A). */
  compat: string;
};

/**
 * Card strip order (spec A, DESIGN-SPEC-v3.md): Touchpad, Air mouse,
 * Keyboard, Presenter & media remote, Macros, iPad layout — paired with
 * surfaces --card-blue, --card-violet, --card-peach, --card-black,
 * --card-mint, --card-gray in that same order. Keep this order if reshuffled.
 */

/** 24×24 stroke icons, inlined so the page loads no external assets. */
function Glyph({ children }: { children: ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width="24"
      height="24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

/**
 * Gesture arcs across a trackpad surface: a swipe trail, a two-finger
 * scroll indicator and a pinch mark — evoking the touchpad's gesture set
 * without trying to be a literal diagram of it.
 */
function TouchpadIllustration() {
  return (
    <svg
      viewBox="0 0 280 140"
      width="280"
      height="140"
      fill="none"
      preserveAspectRatio="xMidYMid meet"
      aria-hidden="true"
      focusable="false"
    >
      <rect
        x="8"
        y="8"
        width="264"
        height="124"
        rx="18"
        stroke="currentColor"
        strokeOpacity="0.3"
        strokeWidth="1.5"
      />
      <path
        d="M46 100c14-30 46-56 84-64"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeDasharray="1 9"
      />
      <circle cx="46" cy="100" r="6" stroke="currentColor" strokeWidth="1.6" />
      <circle cx="130" cy="36" r="5" fill="currentColor" />
      <path
        d="M196 46v46M214 46v46"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeDasharray="1 8"
      />
      <path d="M196 44l-6 10h12z" fill="currentColor" />
      <path d="M214 92l-6-10h12z" fill="currentColor" />
      <path
        d="M236 96l12 12M256 96l-12 12"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      />
    </svg>
  );
}

/**
 * A tilted phone with dashed rays converging on a cursor arrow — the air
 * mouse's "point the phone, the pointer follows" idea in three lines.
 */
function AirMouseIllustration() {
  return (
    <svg
      viewBox="0 0 280 140"
      width="280"
      height="140"
      fill="none"
      preserveAspectRatio="xMidYMid meet"
      aria-hidden="true"
      focusable="false"
    >
      <rect
        x="26"
        y="46"
        width="46"
        height="84"
        rx="10"
        transform="rotate(-16 49 88)"
        stroke="var(--ill-a, currentColor)"
        strokeWidth="1.6"
        strokeOpacity="0.6"
      />
      <path
        d="M70 70l150-40M78 92l150-40M84 114l148-38"
        stroke="var(--ill-b, currentColor)"
        strokeWidth="1.5"
        strokeDasharray="1 8"
        strokeLinecap="round"
      />
      <path d="M232 24l8 20-11-3-3 12-9-24z" fill="var(--ill-b, currentColor)" />
    </svg>
  );
}

/**
 * A 3x2 button deck of rounded pills, each with a tiny glyph — the "define a
 * button, it appears on the phone" idea. One pill is filled to read as
 * pressed, the way a macro button looks the moment it is tapped.
 */
function MacrosIllustration() {
  const columns = [8, 100, 192];
  const rows = [8, 76];
  const pressed = { col: 1, row: 0 };

  return (
    <svg
      viewBox="0 0 280 140"
      width="280"
      height="140"
      fill="none"
      preserveAspectRatio="xMidYMid meet"
      aria-hidden="true"
      focusable="false"
    >
      {rows.map((y, rowIndex) =>
        columns.map((x, colIndex) => {
          const isPressed = rowIndex === pressed.row && colIndex === pressed.col;
          return (
            <g key={`${rowIndex}-${colIndex}`}>
              <rect
                x={x}
                y={y}
                width={80}
                height={56}
                rx="14"
                fill={isPressed ? "var(--ill-a, currentColor)" : "none"}
                fillOpacity={isPressed ? 0.14 : undefined}
                stroke={isPressed ? "var(--ill-a, currentColor)" : "var(--ill-b, currentColor)"}
                strokeOpacity={isPressed ? 0.9 : 0.4}
                strokeWidth="1.5"
              />
              <circle
                cx={x + 40}
                cy={y + 28}
                r="5"
                fill={isPressed ? "var(--ill-a, currentColor)" : "var(--ill-b, currentColor)"}
                fillOpacity={isPressed ? 1 : 0.7}
              />
            </g>
          );
        }),
      )}
    </svg>
  );
}

/**
 * A row of five key caps for the modifier row plus return — ⌘ ⌥ ⌃ ⇧ ⏎ — so
 * the Keyboard card shows the one row of keys that is unique to this app.
 * Drawn on the same 280x140 canvas as the other five illustrations (vs. a
 * short 280x48 strip) so it fills the card's illustration area (spec A)
 * instead of reading as a thin sliver once scaled to the card's full width.
 */
function KeyRowIllustration() {
  const glyphs = ["⌘", "⌥", "⌃", "⇧", "⏎"];
  const gap = 10;
  const keyWidth = (280 - gap * (glyphs.length - 1)) / glyphs.length;
  const keyHeight = 48;
  const y = (140 - keyHeight) / 2;

  return (
    <svg
      viewBox="0 0 280 140"
      width="280"
      height="140"
      fill="none"
      preserveAspectRatio="xMidYMid meet"
      aria-hidden="true"
      focusable="false"
      style={{ fontFamily: "var(--font-sans)" }}
    >
      {glyphs.map((glyph, index) => {
        const x = index * (keyWidth + gap);
        const tint = index % 2 === 0 ? "var(--ill-a, currentColor)" : "var(--ill-b, currentColor)";
        return (
          <g key={glyph}>
            <rect
              x={x}
              y={y}
              width={keyWidth}
              height={keyHeight}
              rx="10"
              stroke={tint}
              strokeOpacity="0.55"
              strokeWidth="1.5"
            />
            <text x={x + keyWidth / 2} y={y + 30} textAnchor="middle" fontSize="18" fill={tint}>
              {glyph}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

/**
 * Three rounded media-remote buttons — previous / play / next — standing in
 * for the presenter's playback controls. Drawn on the same 280x140 canvas as
 * the other five illustrations (see the KeyRowIllustration note above) so it
 * fills the card's illustration area instead of a thin 280x64 sliver.
 */
function MediaRowIllustration() {
  const glyphs = ["⏮︎", "▶︎", "⏭︎"];
  const size = 56;
  const gap = 16;
  const startX = (280 - (glyphs.length * size + (glyphs.length - 1) * gap)) / 2;
  const y = (140 - size) / 2;

  return (
    <svg
      viewBox="0 0 280 140"
      width="280"
      height="140"
      fill="none"
      preserveAspectRatio="xMidYMid meet"
      aria-hidden="true"
      focusable="false"
      style={{ fontFamily: "var(--font-sans)" }}
    >
      {glyphs.map((glyph, index) => {
        const x = startX + index * (size + gap);
        return (
          <g key={glyph}>
            <rect
              x={x}
              y={y}
              width={size}
              height={size}
              rx="16"
              stroke="var(--ill-a, currentColor)"
              strokeOpacity="0.7"
              strokeWidth="1.5"
            />
            <text
              x={x + size / 2}
              y={y + size / 2 + 7}
              textAnchor="middle"
              fontSize="20"
              fill="var(--ill-b, currentColor)"
            >
              {glyph}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

/**
 * A landscape iPad outline: a big touchpad on the left and a narrow column
 * of shortcut-bar keys on the right, for the iPad layout card (spec §3,
 * "a simple iPad outline illustration ... in blue").
 */
function IPadIllustration() {
  const keyYs = [10, 42, 74, 106];

  return (
    <svg
      viewBox="0 0 280 140"
      width="280"
      height="140"
      fill="none"
      preserveAspectRatio="xMidYMid meet"
      aria-hidden="true"
      focusable="false"
    >
      <rect
        x="4"
        y="4"
        width="272"
        height="132"
        rx="16"
        stroke="var(--ill-a, currentColor)"
        strokeOpacity="0.5"
        strokeWidth="2"
      />
      <rect
        x="16"
        y="16"
        width="188"
        height="108"
        rx="12"
        stroke="var(--ill-a, currentColor)"
        strokeOpacity="0.3"
        strokeWidth="1.5"
      />
      {keyYs.map((y) => (
        <rect
          key={y}
          x="216"
          y={y}
          width="48"
          height="24"
          rx="6"
          stroke="var(--ill-a, currentColor)"
          strokeOpacity="0.35"
          strokeWidth="1.5"
        />
      ))}
    </svg>
  );
}

export const features: Feature[] = [
  {
    id: "touchpad",
    title: "Touchpad",
    headline: "Slide. Tap. Scroll. Pinch.",
    benefit:
      "Slide to move the cursor, tap to click, two-finger scroll, pinch to zoom, and three-finger swipes for Mission Control.",
    body: "Your phone's screen is a trackpad: slide to move the cursor, tap to click, two-finger scroll with momentum, pinch to zoom, and three-finger swipes for Mission Control and Spaces.",
    icon: (
      <Glyph>
        <rect x="2.5" y="4.5" width="19" height="15" rx="2.5" />
        <path d="M2.5 15h19" />
      </Glyph>
    ),
    illustration: <TouchpadIllustration />,
    card: "blue",
    compat: "iPhone, iPad",
  },
  {
    id: "air-mouse",
    title: "Air mouse",
    headline: "Point the phone. The cursor follows.",
    benefit:
      "Gyroscope and accelerometer fusion with drift correction and a clutch button that holds the pointer still while you gesture.",
    body: "Point the phone like a laser pointer and the cursor follows — gyroscope and accelerometer fusion with drift correction and a clutch button, so the pointer holds still while you gesture.",
    icon: (
      <Glyph>
        <path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3" />
        <path d="M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1" />
        <circle cx="12" cy="12" r="3.2" />
      </Glyph>
    ),
    illustration: <AirMouseIllustration />,
    card: "violet",
    compat: "iPhone, iPad",
  },
  {
    id: "keyboard",
    title: "Keyboard",
    headline: "Type from the couch.",
    benefit:
      "Types straight into whatever app is frontmost, with modifier chords, arrow and function keys, and a dedicated row for ⌘ ⌥ ⌃ ⇧.",
    body: "Type from the phone straight into whatever app is frontmost on the Mac, with modifier chords, arrow and function keys, and a dedicated row for ⌘, ⌥, ⌃ and ⇧.",
    icon: (
      <Glyph>
        <rect x="2" y="6" width="20" height="12" rx="2" />
        <path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M8 14h8" />
      </Glyph>
    ),
    illustration: <KeyRowIllustration />,
    card: "peach",
    compat: "iPhone, iPad",
  },
  {
    id: "presenter",
    title: "Presenter & media remote",
    headline: "Next slide, without looking.",
    benefit:
      "Large next, previous and blank-screen buttons you can hit without looking, plus volume, play-pause and track skip controls.",
    body: "Large next / previous / blank-screen buttons you can hit without looking, plus volume, play-pause and track skip that talk to whatever is playing on the Mac.",
    icon: (
      <Glyph>
        <rect x="2.5" y="4" width="19" height="12.5" rx="2" />
        <path d="M8 20h8M12 16.5V20" />
        <path d="M10 8.2l4 2.05-4 2.05z" />
      </Glyph>
    ),
    illustration: <MediaRowIllustration />,
    card: "black",
    compat: "iPhone, iPad",
  },
  {
    id: "macros",
    title: "Macros",
    headline: "Your shortcuts, as buttons.",
    benefit:
      "Define a key combo, an app or a Shortcut on the Mac, and it appears as a button on the phone.",
    body: "Define buttons on the Mac — a key combo, an app to launch, a Shortcut to run — and they appear as a button deck on the phone, with scripts kept behind an explicit opt-in.",
    icon: (
      <Glyph>
        <rect x="3" y="3" width="7.5" height="7.5" rx="1.8" />
        <rect x="13.5" y="3" width="7.5" height="7.5" rx="1.8" />
        <rect x="3" y="13.5" width="7.5" height="7.5" rx="1.8" />
        <rect x="13.5" y="13.5" width="7.5" height="7.5" rx="1.8" />
      </Glyph>
    ),
    illustration: <MacrosIllustration />,
    card: "mint",
    compat: "iPhone, iPad",
  },
  {
    id: "ipad",
    title: "iPad layout",
    headline: "Bigger pad. Same speed.",
    benefit:
      "An oversized touchpad plus a persistent keyboard and shortcut bar in landscape, with hardware keyboard pass-through.",
    body: "In landscape the iPad shows an oversized touchpad and a persistent keyboard and shortcut bar side by side, and passes an attached hardware keyboard straight through.",
    icon: (
      <Glyph>
        <rect x="4" y="2.5" width="16" height="19" rx="2.2" />
        <path d="M10.5 19h3" />
      </Glyph>
    ),
    illustration: <IPadIllustration />,
    card: "gray",
    compat: "iPad",
  },
];

/* -------------------------------------------------------------------------- */
/* Devices row — three 64px line-icon SVGs (spec §4)                          */
/* -------------------------------------------------------------------------- */

/** 64x64 stroke icons, black line-art (tinted via `.devices__icon` in sections.css). */
function DeviceGlyph({ children }: { children: ReactNode }) {
  return (
    <svg
      viewBox="0 0 64 64"
      width="64"
      height="64"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

function IPhoneDeviceIcon() {
  return (
    <DeviceGlyph>
      <rect x="20" y="4" width="24" height="56" rx="6.5" />
      <rect x="27" y="10" width="10" height="4" rx="2" fill="currentColor" stroke="none" />
    </DeviceGlyph>
  );
}

function IPadDeviceIcon() {
  return (
    <DeviceGlyph>
      <rect x="10" y="7" width="44" height="50" rx="5" />
      <circle cx="32" cy="14.5" r="1.4" fill="currentColor" stroke="none" />
    </DeviceGlyph>
  );
}

function MacDeviceIcon() {
  return (
    <DeviceGlyph>
      <rect x="10" y="12" width="44" height="30" rx="3" />
      <path d="M4 46h56l-6 8H10z" />
    </DeviceGlyph>
  );
}

export type Device = {
  id: string;
  label: string;
  icon: ReactNode;
  /** e.g. "iOS 18 or later" — derived from `site.minimumOS`. */
  requirement: string;
};

// site.minimumOS.ios reads "iOS 18 / iPadOS 18" — split it for the iPhone/iPad columns.
const [iosRequirement, ipadosRequirement] = site.minimumOS.ios.split(" / ");

export const devices: Device[] = [
  {
    id: "iphone",
    label: "iPhone",
    icon: <IPhoneDeviceIcon />,
    requirement: `${iosRequirement} or later`,
  },
  {
    id: "ipad",
    label: "iPad",
    icon: <IPadDeviceIcon />,
    requirement: `${ipadosRequirement ?? iosRequirement} or later`,
  },
  {
    id: "mac",
    label: "Mac",
    icon: <MacDeviceIcon />,
    requirement: `${site.minimumOS.macos} or later`,
  },
];

/* -------------------------------------------------------------------------- */
/* How it works                                                               */
/* -------------------------------------------------------------------------- */

export const steps = [
  {
    title: "Install the Mac helper",
    body: "A menu-bar app that asks for Accessibility once — its only permission — then starts at login and stays out of the way.",
  },
  {
    title: "Scan the QR code",
    body: "Point your phone at the QR code the helper shows, carrying a one-time secret that expires in 60 seconds.",
  },
  {
    title: "Take control",
    body: "The phone lands on the touchpad and reconnects on its own from then on, every time.",
  },
];

/* -------------------------------------------------------------------------- */
/* Value cards — two-up trust cards above the security pillars (spec §7)      */
/* -------------------------------------------------------------------------- */

/** Which `--card-*` surface a value card uses: dark aurora gradient or the solid blue. */
export type ValueCardTone = "aurora" | "solid-blue";

export type ValueCard = {
  id: string;
  tone: ValueCardTone;
  icon: ReactNode;
  headline: string;
  body: string;
  linkLabel: string;
  href: string;
};

function LockIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      width="22"
      height="22"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <rect x="5" y="11" width="14" height="9" rx="2.2" />
      <path d="M8 11V8a4 4 0 0 1 8 0v3" />
      <circle cx="12" cy="15.3" r="1.3" fill="currentColor" stroke="none" />
    </svg>
  );
}

/** A "</>" glyph standing in for "open source". */
function OpenSourceIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      width="22"
      height="22"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M9 6.5l-5.5 5.5L9 17.5M15 6.5l5.5 5.5-5.5 5.5" />
    </svg>
  );
}

export const valueCards: ValueCard[] = [
  {
    id: "privacy",
    tone: "aurora",
    icon: <LockIcon />,
    headline: "Your keystrokes never leave your network.",
    body: "Local Wi‑Fi only, mutual TLS 1.3, and a one-time pairing secret — nothing about what you type or click is ever sent anywhere else.",
    linkLabel: "Read the threat model",
    href: site.links.security,
  },
  {
    id: "open-source",
    tone: "solid-blue",
    icon: <OpenSourceIcon />,
    headline: "Open. Free. Yours.",
    body: "MIT licensed and native Swift throughout — both apps and the wire protocol they speak are public, so you can read every line that touches your Mac.",
    linkLabel: "View on GitHub",
    href: site.links.github,
  },
];

/* -------------------------------------------------------------------------- */
/* Security                                                                   */
/* -------------------------------------------------------------------------- */

/**
 * Three pillars shown on the landing page's Security section, below the
 * two-up value cards (spec §7) — a condensed, landing-page-scale summary;
 * SECURITY.md carries the complete threat model.
 */
export type SecurityPillar = {
  title: string;
  body: string;
  /** 24×24 stroke icon shown in a 56px accent-tint square (see .pillar__glyph). */
  icon: ReactNode;
};

export const securityPillars: SecurityPillar[] = [
  {
    title: "Local Wi‑Fi only",
    body: "No relay, no cloud, no server in the middle — the phone talks to your Mac directly.",
    icon: (
      <Glyph>
        <path d="M4 12a11 11 0 0 1 16 0" />
        <path d="M7.4 15.6a6.4 6.4 0 0 1 9.2 0" />
        <circle cx="12" cy="19" r="1.3" fill="currentColor" stroke="none" />
      </Glyph>
    ),
  },
  {
    title: "Mutual TLS 1.3",
    body: "Both ends verify each other's certificate; motion packets carry authenticated encryption with replay protection.",
    icon: (
      <Glyph>
        <path d="M12 3l7 3v5c0 5-3 8.5-7 10-4-1.5-7-5-7-10V6z" />
        <path d="M9 12l2 2 4-4" />
      </Glyph>
    ),
  },
  {
    title: "One-time pairing",
    body: "The QR secret is valid for 60 seconds and used once; only paired devices are accepted, revocable from either end.",
    icon: (
      <Glyph>
        <rect x="3.5" y="3.5" width="6" height="6" rx="1" />
        <rect x="14.5" y="3.5" width="6" height="6" rx="1" />
        <rect x="3.5" y="14.5" width="6" height="6" rx="1" />
        <path d="M14.5 14.5h2.2v2.2h-2.2zM19 14.5v2.2M14.5 19h2M19 19h1.5" />
      </Glyph>
    ),
  },
];

/* -------------------------------------------------------------------------- */
/* Stats band — four proof points, shown as giant numbers on a black band.    */
/* -------------------------------------------------------------------------- */

export const stats: { value: string; caption: string }[] = [
  { value: "< 20 ms", caption: "motion latency, design target on 5 GHz Wi‑Fi" },
  { value: "0", caption: "accounts, sign-ins or servers" },
  { value: "0 bytes", caption: "of telemetry, ever" },
  { value: "MIT", caption: "licensed and fully open" },
];

/* -------------------------------------------------------------------------- */
/* FAQ                                                                        */
/* -------------------------------------------------------------------------- */

export const faqs: { q: string; a: ReactNode; plain: string }[] = [
  {
    q: "What do I need to run it?",
    a: (
      <>
        {site.minimumOS.macos} or later on the Mac, and {site.minimumOS.ios} or
        later on the iPhone or iPad. Both devices need to be on the same Wi‑Fi
        network (or the Mac joined to the phone&rsquo;s hotspot).
      </>
    ),
    plain: `${site.minimumOS.macos} or later on the Mac, and ${site.minimumOS.ios} or later on the iPhone or iPad. Both devices need to be on the same Wi-Fi network, or the Mac joined to the phone's hotspot.`,
  },
  {
    q: "Why does the Mac helper need Accessibility permission?",
    a: (
      <>
        Moving the cursor and pressing keys on your behalf is exactly what the
        Accessibility permission governs on macOS, so there is no way around it.
        It is the only permission the helper asks for — it never requests Input
        Monitoring or Screen Recording, so it cannot read your keystrokes or see
        your screen.
      </>
    ),
    plain:
      "Moving the cursor and pressing keys on your behalf is what the Accessibility permission governs on macOS. It is the only permission the helper asks for; it never requests Input Monitoring or Screen Recording, so it cannot read your keystrokes or see your screen.",
  },
  {
    q: "Does it work without an internet connection?",
    a: (
      <>
        Yes. Everything happens on the local network. A router with no uplink,
        or the phone&rsquo;s own hotspot, is enough — Air Control never needs to
        reach the internet to pair, connect or run.
      </>
    ),
    plain:
      "Yes. Everything happens on the local network. A router with no uplink, or the phone's own hotspot, is enough.",
  },
  {
    q: "Does it use Bluetooth?",
    a: (
      <>
        No — Wi‑Fi only. iOS does not let an app act as a Bluetooth HID
        peripheral, so a Bluetooth mouse or keyboard is not something any iPhone
        app can offer. Wi‑Fi is also considerably faster.
      </>
    ),
    plain:
      "No, Wi-Fi only. iOS does not let an app act as a Bluetooth HID peripheral, so a Bluetooth mouse or keyboard is not something any iPhone app can offer. Wi-Fi is also considerably faster.",
  },
  {
    q: "Does it support iPad?",
    a: (
      <>
        Yes. The iPad gets its own landscape layout with a large touchpad
        alongside a persistent keyboard and shortcut bar, and it passes an
        attached hardware keyboard through to the Mac.
      </>
    ),
    plain:
      "Yes. The iPad gets its own landscape layout with a large touchpad alongside a persistent keyboard and shortcut bar, and it passes an attached hardware keyboard through to the Mac.",
  },
  {
    q: "What does it cost?",
    a: (
      <>
        Nothing. Air Control is free and MIT-licensed, with no subscription, no
        paid tier and no ads. If it is useful, the repository takes issues and
        pull requests.
      </>
    ),
    plain:
      "Nothing. Air Control is free and MIT-licensed, with no subscription, no paid tier and no ads.",
  },
];
