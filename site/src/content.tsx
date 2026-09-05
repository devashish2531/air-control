import type { ReactNode } from "react";

import { site } from "@/site.config";

/* -------------------------------------------------------------------------- */
/* Features — one sentence each, drawn from docs/01-requirements.md §3.        */
/* -------------------------------------------------------------------------- */

export type Feature = {
  id: string;
  title: string;
  body: string;
  /** Decorative: the section heading already names the feature. */
  icon: ReactNode;
  /**
   * Small decorative line-art shown only inside the two `.tile--wide` bento
   * tiles (Touchpad, Air mouse). Purely illustrative — aria-hidden by the
   * caller — so it never duplicates information the title/body already give.
   */
  illustration?: ReactNode;
};

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
        stroke="currentColor"
        strokeWidth="1.6"
        strokeOpacity="0.6"
      />
      <path
        d="M70 70l150-40M78 92l150-40M84 114l148-38"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeDasharray="1 8"
        strokeLinecap="round"
      />
      <path d="M232 24l8 20-11-3-3 12-9-24z" fill="currentColor" />
    </svg>
  );
}

export const features: Feature[] = [
  {
    id: "touchpad",
    title: "Touchpad",
    body: "Your phone's screen is a trackpad: slide to move the cursor, tap to click, two-finger scroll with momentum, pinch to zoom, and three-finger swipes for Mission Control and Spaces.",
    icon: (
      <Glyph>
        <rect x="2.5" y="4.5" width="19" height="15" rx="2.5" />
        <path d="M2.5 15h19" />
      </Glyph>
    ),
    illustration: <TouchpadIllustration />,
  },
  {
    id: "air-mouse",
    title: "Air mouse",
    body: "Point the phone like a laser pointer and the cursor follows — gyroscope and accelerometer fusion with drift correction and a clutch button, so the pointer holds still while you gesture.",
    icon: (
      <Glyph>
        <path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3" />
        <path d="M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1" />
        <circle cx="12" cy="12" r="3.2" />
      </Glyph>
    ),
    illustration: <AirMouseIllustration />,
  },
  {
    id: "keyboard",
    title: "Keyboard",
    body: "Type from the phone straight into whatever app is frontmost on the Mac, with modifier chords, arrow and function keys, and a dedicated row for ⌘, ⌥, ⌃ and ⇧.",
    icon: (
      <Glyph>
        <rect x="2" y="6" width="20" height="12" rx="2" />
        <path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M8 14h8" />
      </Glyph>
    ),
  },
  {
    id: "presenter",
    title: "Presenter & media remote",
    body: "Large next / previous / blank-screen buttons you can hit without looking, plus volume, play-pause and track skip that talk to whatever is playing on the Mac.",
    icon: (
      <Glyph>
        <rect x="2.5" y="4" width="19" height="12.5" rx="2" />
        <path d="M8 20h8M12 16.5V20" />
        <path d="M10 8.2l4 2.05-4 2.05z" />
      </Glyph>
    ),
  },
  {
    id: "macros",
    title: "Macros",
    body: "Define buttons on the Mac — a key combo, an app to launch, a Shortcut to run — and they appear as a button deck on the phone, with scripts kept behind an explicit opt-in.",
    icon: (
      <Glyph>
        <rect x="3" y="3" width="7.5" height="7.5" rx="1.8" />
        <rect x="13.5" y="3" width="7.5" height="7.5" rx="1.8" />
        <rect x="3" y="13.5" width="7.5" height="7.5" rx="1.8" />
        <rect x="13.5" y="13.5" width="7.5" height="7.5" rx="1.8" />
      </Glyph>
    ),
  },
  {
    id: "ipad",
    title: "iPad layout",
    body: "In landscape the iPad shows an oversized touchpad and a persistent keyboard and shortcut bar side by side, and passes an attached hardware keyboard straight through.",
    icon: (
      <Glyph>
        <rect x="4" y="2.5" width="16" height="19" rx="2.2" />
        <path d="M10.5 19h3" />
      </Glyph>
    ),
  },
];

/* -------------------------------------------------------------------------- */
/* How it works                                                               */
/* -------------------------------------------------------------------------- */

export const steps = [
  {
    title: "Install the Mac helper",
    body: "A small menu-bar app. Grant it Accessibility once — that is the only permission it asks for — and it starts at login and stays out of your way.",
  },
  {
    title: "Scan the QR code",
    body: "The helper shows a QR code containing its address, its certificate fingerprint and a one-time secret that expires in 60 seconds. Point the phone at it.",
  },
  {
    title: "Take control",
    body: "The phone lands on the touchpad and reconnects on its own from then on. Swipe between touchpad, air mouse, keyboard, remote and your macros.",
  },
];

/* -------------------------------------------------------------------------- */
/* Security                                                                   */
/* -------------------------------------------------------------------------- */

export type SecurityPoint = {
  title: string;
  body: string;
  /** 24×24 stroke icon shown in a 32px accent-tint square (see .security__glyph). */
  icon: ReactNode;
};

export const securityPoints: SecurityPoint[] = [
  {
    title: "Local network only",
    body: "The phone talks to your Mac directly over your Wi‑Fi. There is no relay, no cloud, no server in the middle — and nothing to sign in to.",
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
    body: "Both ends hold their own certificate and each verifies the other's. Motion packets on the low-latency UDP path carry their own authenticated encryption with replay protection.",
    icon: (
      <Glyph>
        <path d="M12 3l7 3v5c0 5-3 8.5-7 10-4-1.5-7-5-7-10V6z" />
        <path d="M9 12l2 2 4-4" />
      </Glyph>
    ),
  },
  {
    title: "One-time pairing code",
    body: "The QR code carries a secret that is valid for 60 seconds and can be used exactly once. A photograph of it afterwards is worthless.",
    icon: (
      <Glyph>
        <rect x="3.5" y="3.5" width="6" height="6" rx="1" />
        <rect x="14.5" y="3.5" width="6" height="6" rx="1" />
        <rect x="3.5" y="14.5" width="6" height="6" rx="1" />
        <path d="M14.5 14.5h2.2v2.2h-2.2zM19 14.5v2.2M14.5 19h2M19 19h1.5" />
      </Glyph>
    ),
  },
  {
    title: "Only devices you paired",
    body: "Any device presenting a certificate that is not on the Mac's trusted list is refused at the handshake. You can revoke a phone from either end at any time.",
    icon: (
      <Glyph>
        <circle cx="12" cy="12" r="7.5" />
        <path d="M12 8v.01" />
        <path d="M8.7 10.2c.5-1.6 1.8-2.6 3.3-2.6s2.8 1 3.3 2.6M7.3 13c.4-2.8 2.4-4.9 4.7-4.9s4.3 2.1 4.7 4.9M6.3 16c.6-4 3.3-7 5.7-7s5.1 3 5.7 7" />
      </Glyph>
    ),
  },
  {
    title: "No telemetry",
    body: "Nothing is collected, counted or phoned home. The latency HUD and diagnostics export exist for you, not for us.",
    icon: (
      <Glyph>
        <path d="M3 3l18 18" />
        <path d="M10.6 5.4A10.4 10.4 0 0 1 12 5.3c5 0 8.5 3.5 9.8 6.7-.5 1.2-1.3 2.6-2.4 3.9M6.6 6.6C4.3 8.1 2.6 10.2 1.7 12c1.3 3.2 4.8 6.7 9.8 6.7 1.5 0 2.9-.3 4.1-.9" />
        <path d="M9.9 10a3 3 0 0 0 4.1 4.1" />
      </Glyph>
    ),
  },
  {
    title: "Open source",
    body: "The protocol, the crypto and both apps are public and auditable. The threat model and reporting process live in SECURITY.md.",
    icon: (
      <Glyph>
        <path d="M9 6l-6 6 6 6M15 6l6 6-6 6" />
      </Glyph>
    ),
  },
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
