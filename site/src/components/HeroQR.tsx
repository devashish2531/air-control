import QRCode from "qrcode";

import { Reveal } from "@/components/Reveal";
import { site } from "@/site.config";

/**
 * Hero QR card (design spec v3 §C). This is an **async server component**:
 * `qrcode` runs once at build time to produce an SVG string, which is
 * inlined into the static HTML. The `qrcode` package itself never ships to
 * the browser — there is no client bundle for this component, no JS runs to
 * draw the code, and nothing here is interactive. (`<Reveal>` is a client
 * component, same as `HeroDevice` already renders — it only toggles a class
 * on scroll-into-view; it does not touch the QR markup itself.)
 *
 * Target is `site.qr.target` — the hero's iPhone link
 * (`id="get-iphone"`, see Hero.tsx), not the bare origin, so scanning drops
 * the visitor straight onto the action that matters. Swap `site.qr.target`
 * for the App Store URL once the iPhone app is published (see the comment
 * next to it in site.config.ts).
 *
 * `margin: 0` + a transparent light color means the SVG carries no quiet
 * zone of its own — the white `.hero__qr` card's own padding is the quiet
 * zone instead, so the code still scans cleanly.
 */
export async function HeroQR() {
  const svg = await QRCode.toString(site.qr.target, {
    type: "svg",
    margin: 0,
    errorCorrectionLevel: "M",
    color: { dark: "#1d1d1f", light: "#0000" },
  });

  return (
    <Reveal as="div" className="hero__qr" delay={400}>
      <div
        className="qr"
        role="img"
        aria-label="QR code linking to the Air Control download page for iPhone"
        // `svg` is a build-time string this module generated itself from a
        // fixed, non-user-controlled URL — not user input.
        dangerouslySetInnerHTML={{ __html: svg }}
      />
      <p className="hero__qr-caption">Scan to get it on your iPhone</p>
      <p className="hero__qr-subcaption">Coming soon · join the waitlist</p>
    </Reveal>
  );
}
