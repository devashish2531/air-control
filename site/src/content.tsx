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

export const securityPoints = [
  {
    title: "Local network only",
    body: "The phone talks to your Mac directly over your Wi‑Fi. There is no relay, no cloud, no server in the middle — and nothing to sign in to.",
  },
  {
    title: "Mutual TLS 1.3",
    body: "Both ends hold their own certificate and each verifies the other's. Motion packets on the low-latency UDP path carry their own authenticated encryption with replay protection.",
  },
  {
    title: "One-time pairing code",
    body: "The QR code carries a secret that is valid for 60 seconds and can be used exactly once. A photograph of it afterwards is worthless.",
  },
  {
    title: "Only devices you paired",
    body: "Any device presenting a certificate that is not on the Mac's trusted list is refused at the handshake. You can revoke a phone from either end at any time.",
  },
  {
    title: "No telemetry",
    body: "Nothing is collected, counted or phoned home. The latency HUD and diagnostics export exist for you, not for us.",
  },
  {
    title: "Open source",
    body: "The protocol, the crypto and both apps are public and auditable. The threat model and reporting process live in SECURITY.md.",
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
