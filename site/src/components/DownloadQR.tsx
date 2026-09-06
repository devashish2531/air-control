import QRCode from "qrcode";

import { site } from "@/site.config";

/**
 * Download-section QR code (design spec v4 §C2). Same generation pattern as
 * `HeroQR.tsx`: an **async server component** — `qrcode` runs once at build
 * time, producing an SVG string that is inlined into the static HTML via
 * `dangerouslySetInnerHTML`. `qrcode` never ships to the browser and nothing
 * here is interactive.
 *
 * Target is the same `site.qr.target` the hero QR uses (the hero's iPhone
 * link, `#get-iphone`) — one canonical destination for every QR on the page.
 * `margin: 0` + a transparent light color means the SVG carries no quiet zone
 * of its own; the caller's own padding/whitespace around `<DownloadQR>` is
 * the quiet zone instead, same as `HeroQR`.
 */
export async function DownloadQR({ size = 96 }: { size?: number }) {
  const svg = await QRCode.toString(site.qr.target, {
    type: "svg",
    margin: 0,
    errorCorrectionLevel: "M",
    color: { dark: "#1d1d1f", light: "#0000" },
  });

  return (
    <div
      className="download-qr"
      role="img"
      aria-label="QR code linking to the Air Control download page"
      style={{ width: size, height: size }}
      // `svg` is a build-time string this module generated itself from a
      // fixed, non-user-controlled URL — not user input.
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}
