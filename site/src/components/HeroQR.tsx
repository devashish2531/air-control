import type { CSSProperties } from "react";

import QRCode from "qrcode";

import { site } from "@/site.config";

/**
 * Same helper as components/Hero.tsx's `inDelay` — not imported from there
 * to avoid a cycle (Hero.tsx imports this module). Drives the `.hero__in` +
 * `--in-delay` entrance hook (hero.css, DESIGN-SPEC-v6.md §B.1), extended to
 * this card at a 360ms delay (after the actions row at 270ms).
 */
function inDelay(ms: number): CSSProperties {
  return { "--in-delay": `${ms}ms` } as CSSProperties;
}

/**
 * Hero QR card (DESIGN-SPEC-v6.md §A) — the hero's right column at >= 64rem
 * (~38%, vertically centered against the copy); below 64rem it sits under
 * the actions row, full width; below 40rem the QR stacks above the text
 * (hero.css `.hero__qr-card`). This is an **async server component**:
 * `qrcode` runs once at build time to produce an SVG string, which is
 * inlined into the static HTML. The `qrcode` package itself never ships to
 * the browser — there is no client bundle for this component, no JS runs to
 * draw the code, and nothing here is interactive (no `<Reveal>`: the entrance
 * is the same load-triggered CSS keyframe as the rest of the hero copy, not
 * a scroll-into-view reveal).
 *
 * Target is `site.qr.target` — the hero's iPhone link (`id="get-iphone"`,
 * see Hero.tsx), not the bare origin, so scanning drops the visitor straight
 * onto the action that matters. Swap `site.qr.target` for the App Store URL
 * once the iPhone app is published (see the comment next to it in
 * site.config.ts).
 *
 * `margin: 0` + a transparent light color means the SVG carries no quiet
 * zone of its own — the card's own padding stands in for it.
 */
export async function HeroQR() {
  const svg = await QRCode.toString(site.qr.target, {
    type: "svg",
    margin: 0,
    errorCorrectionLevel: "M",
    color: { dark: "#1d1d1f", light: "#0000" },
  });

  return (
    <div className="hero__in hero__qr-card" style={inDelay(360)}>
      <div
        className="qr"
        role="img"
        aria-label="QR code linking to the Air Control download page for iPhone"
        // `svg` is a build-time string this module generated itself from a
        // fixed, non-user-controlled URL — not user input.
        dangerouslySetInnerHTML={{ __html: svg }}
      />
      <div className="hero__qr-body">
        <p className="hero__qr-title">Get it on iPhone</p>
        <p className="hero__qr-desc">
          Scan with your camera to open this page on your phone, then join
          the waitlist.
        </p>
        <a
          className="link-arrow"
          href={site.links.iosWaitlist}
          rel="noreferrer noopener"
        >
          Join the waitlist
          <span className="link-arrow__chevron" aria-hidden="true">
            ›
          </span>
        </a>
      </div>
    </div>
  );
}
