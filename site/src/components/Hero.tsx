import type { CSSProperties } from "react";

import { HeroDevice } from "@/components/HeroDevice";
import { HeroQR } from "@/components/HeroQR";
import { site } from "@/site.config";

/**
 * Staggered load-in delay for the `.hero__in` entrance animation defined in
 * hero.css (spec: hero spec, "Load-in" — 0/80/160/240/320ms across the five
 * text blocks). CSSProperties has no index signature for custom properties,
 * hence the cast — same pattern as components/Reveal.tsx.
 */
function inDelay(ms: number): CSSProperties {
  return { "--in-delay": `${ms}ms` } as CSSProperties;
}

export function Hero() {
  const requirements = `Requires ${site.minimumOS.macos} and ${site.minimumOS.ios} or later.`;

  return (
    <section className="hero" id="top">
      <div className="container hero__inner">
        <p className="hero__in hero__eyebrow-line" style={inDelay(0)}>
          <span className="badge">Free · Open source · Local Wi‑Fi only</span>
        </p>

        <h1 className="display hero__title hero__in" style={inDelay(80)}>
          Your iPhone. <span className="grad-text">Now a trackpad for your Mac.</span>
        </h1>

        <p className="lede hero__lede hero__in" style={inDelay(160)}>
          Air Control turns your iPhone or iPad into a trackpad, air mouse,
          keyboard and presenter remote — over your own Wi‑Fi, with nothing in
          between.
        </p>

        <div className="hero__actions hero__in" style={inDelay(240)}>
          <a
            className="button button--primary"
            href={site.links.latestRelease}
            rel="noreferrer noopener"
          >
            Download for Mac
          </a>

          {/* id="get-iphone": the hero QR card's scan target (spec §C) —
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

        <div className="hero__meta hero__in" style={inDelay(320)}>
          <p className="small hero__requirements">{requirements}</p>
        </div>

        <div className="hero__stage">
          <HeroDevice />
          <HeroQR />
        </div>
      </div>
    </section>
  );
}
