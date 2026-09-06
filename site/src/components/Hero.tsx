import type { CSSProperties } from "react";

import { BuiltWith } from "@/components/BuiltWith";
import { HeroDevice } from "@/components/HeroDevice";
import { HeroQR } from "@/components/HeroQR";
import { site } from "@/site.config";

/**
 * Staggered load-in delay for the `.hero__in` entrance animation defined in
 * hero.css (DESIGN-SPEC-v6.md §B.1 — `hero-rise`, 0/90/180/270/360ms across
 * eyebrow/h1/lede/actions/QR card). CSSProperties has no index signature for
 * custom properties, hence the cast — same pattern as components/Reveal.tsx.
 */
function inDelay(ms: number): CSSProperties {
  return { "--in-delay": `${ms}ms` } as CSSProperties;
}

export function Hero() {
  return (
    <section className="hero" id="top">
      <div className="container hero__inner">
        {/* Two-column top block at >= 64rem (spec §A): copy left (~58%),
            .hero__qr-card right (~38%, vertically centered). Below 64rem
            the grid collapses to one column and the card falls in normal
            flow under the actions row; below 40rem the card itself stacks
            the QR above its text (hero.css). */}
        <div className="hero__top">
          <div className="hero__copy">
            <p className="hero__in hero__eyebrow" style={inDelay(0)}>
              Air Control for iPhone and Mac
            </p>

            <h1 className="display hero__title hero__in" style={inDelay(90)}>
              Your iPhone. <span className="grad-text">Now a trackpad for your Mac.</span>
            </h1>

            <p className="lede hero__lede hero__in" style={inDelay(180)}>
              Also an air pointer, keyboard and presenter remote, all over Wi‑Fi.
            </p>

            {/* Two action rows, toggled purely by CSS (hero.css) — no
                user-agent sniffing. `--desktop` (>= 48rem): primary is the
                Mac download, matching a pointer/desktop visitor's likely
                platform; `--mobile` (< 48rem): primary is the iPhone
                download instead, since a phone visitor is almost certainly
                on the device the mobile CTA targets. Only one row is ever
                in the layout (display: none on the other), so there is
                never a duplicate tab stop. */}
            <div
              className="hero__actions hero__actions--desktop hero__in"
              style={inDelay(270)}
            >
              <a
                className="button button--primary"
                href={site.links.latestRelease}
                rel="noreferrer noopener"
              >
                Download for Mac
              </a>

              {/* id="get-iphone": the hero QR card's scan target (spec §A) —
                  scanning it should land right on this action. */}
              <span className="hero__waitlist" id="get-iphone">
                <a
                  className="link-arrow"
                  href={site.links.iosWaitlist}
                  rel="noreferrer noopener"
                >
                  Get it for iPhone
                  <span className="link-arrow__chevron" aria-hidden="true">
                    ›
                  </span>
                </a>
                <span className="badge">Coming soon</span>
              </span>
            </div>

            <div
              className="hero__actions hero__actions--mobile hero__in"
              style={inDelay(270)}
            >
              <span className="hero__waitlist">
                <a
                  className="button button--primary"
                  href={site.links.iosWaitlist}
                  rel="noreferrer noopener"
                >
                  Download for iPhone
                </a>
                <span className="badge">Coming soon</span>
              </span>

              <a
                className="link-arrow"
                href={site.links.latestRelease}
                rel="noreferrer noopener"
              >
                Get it for Mac
                <span className="link-arrow__chevron" aria-hidden="true">
                  ›
                </span>
              </a>
            </div>
          </div>

          {/* Right column at >= 64rem: QR card, then the "Built with" strip
              stacked underneath it (builtwith.css `.hero__aside`), same
              width as the QR card. Stacks under the copy in normal flow
              below 64rem — QR card, then Built-with. */}
          <div className="hero__aside">
            <HeroQR />
            <BuiltWith />
          </div>
        </div>

        {/* Plain positioning wrapper (no stage panel, no floating card) —
            the product mock floats on white with its own shadows. */}
        <div className="hero__composition">
          <HeroDevice />
        </div>
      </div>
    </section>
  );
}
