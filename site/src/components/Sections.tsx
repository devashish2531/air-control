import { CardStrip } from "@/components/CardStrip";
import { Reveal } from "@/components/Reveal";
import {
  devices,
  faqs,
  features,
  securityPillars,
  stats,
  steps,
  valueCards,
  type Feature,
} from "@/content";
import { site } from "@/site.config";

/** Stagger delay for the Nth sibling in a revealed group, capped per spec (~300ms). */
function stagger(index: number): number {
  return Math.min(index * 60, 300);
}

function ChevronIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      width="20"
      height="20"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M9 6l6 6-6 6" />
    </svg>
  );
}

/**
 * One card in the feature strip: glyph + name row, punchy headline,
 * one-sentence benefit, illustration filling the middle, and a
 * "Compatibility" footer (spec A). Server-rendered — `CardStrip` only owns
 * the scroll mechanics around it, so this copy stays in the initial HTML.
 */
function FeatureCard({ feature }: { feature: Feature }) {
  return (
    <article className={`strip-card strip-card--${feature.card}`}>
      <div className="strip-card__top">
        <span className="strip-card__glyph">{feature.icon}</span>
        <h3 className="strip-card__name">{feature.title}</h3>
      </div>
      <p className="strip-card__headline">{feature.headline}</p>
      <p className="strip-card__benefit">{feature.benefit}</p>
      {feature.illustration && (
        <div className="strip-card__illustration" aria-hidden="true">
          {feature.illustration}
        </div>
      )}
      <p className="strip-card__compat">
        <span className="strip-card__compat-label">Compatibility</span>
        <span className="strip-card__compat-value">{feature.compat}</span>
      </p>
    </article>
  );
}

/**
 * The landing page's centerpiece: a horizontal strip of six tall portrait
 * cards that scroll sideways with prev/next buttons, Apple's apple.com/apps
 * "Health & Fitness" strip style (spec A). `features` is already ordered
 * Touchpad, Air mouse, Keyboard, Presenter & media remote, Macros, iPad
 * layout — see the ordering note on `features` in content.tsx. The whole
 * strip reveals once (no per-card stagger — a scroll container makes
 * staggering odd).
 */
export function Features() {
  return (
    <section className="section" id="features" aria-labelledby="features-title">
      <div className="container--wide">
        <Reveal as="div" className="section__head section__head--start">
          <span className="eyebrow">What it does</span>
          <h2 className="h2" id="features-title">
            One phone. <span className="muted">Every way to drive your Mac.</span>
          </h2>
        </Reveal>
      </div>

      <Reveal as="div">
        <CardStrip>
          {features.map((feature) => (
            <FeatureCard feature={feature} key={feature.id} />
          ))}
        </CardStrip>
      </Reveal>
    </section>
  );
}

/** Three device columns (iPhone, iPad, Mac): 64px line icon, label, OS requirement. */
export function Devices() {
  return (
    <section
      className="section section--tint"
      id="devices"
      aria-labelledby="devices-title"
    >
      <div className="container">
        <Reveal as="div" className="section__head">
          <h2 className="h2" id="devices-title">
            Works on the devices{" "}
            <span className="muted">you already own.</span>
          </h2>
        </Reveal>

        <div className="devices-row">
          {devices.map((device, index) => (
            <Reveal
              as="div"
              key={device.id}
              delay={stagger(index)}
              className="devices-row__item"
            >
              <span className="devices-row__icon">{device.icon}</span>
              <h3 className="devices-row__label">{device.label}</h3>
              <p className="small devices-row__requirement">{device.requirement}</p>
            </Reveal>
          ))}
        </div>

        <Reveal
          as="div"
          className="devices-row__links"
          delay={stagger(devices.length)}
        >
          <a
            className="link-arrow"
            href={site.links.latestRelease}
            rel="noreferrer noopener"
          >
            Download for Mac
            <span className="link-arrow__chevron" aria-hidden="true">
              ›
            </span>
          </a>
          <a
            className="link-arrow"
            href={site.links.iosWaitlist}
            rel="noreferrer noopener"
          >
            Join the iPhone waitlist
            <span className="link-arrow__chevron" aria-hidden="true">
              ›
            </span>
          </a>
        </Reveal>
      </div>
    </section>
  );
}

/** Full-bleed black band: four proof points, each a solid white number. */
export function Stats() {
  return (
    <section
      className="section band--dark"
      id="numbers"
      aria-labelledby="numbers-title"
    >
      <div className="container--wide">
        {/* Visually the numbers speak for themselves — this heading exists
            for the accessibility tree and the h1 -> h2 -> h3 outline, not as
            on-page copy. */}
        <h2 className="visually-hidden" id="numbers-title">
          Air Control by the numbers
        </h2>

        <div className="stats-grid">
          {stats.map((stat, index) => (
            <Reveal as="div" key={stat.caption} delay={stagger(index)}>
              <p className="stat-item__value">{stat.value}</p>
              <p className="stat-item__caption">{stat.caption}</p>
            </Reveal>
          ))}
        </div>

        <Reveal as="p" className="small stats-note" delay={stagger(stats.length)}>
          Latency is a goal the project measures itself against, not a
          guarantee — your router and distance get a vote. The app ships a
          latency HUD so you can see the real number on your own network.
        </Reveal>
      </div>
    </section>
  );
}

export function HowItWorks() {
  return (
    <section
      className="section"
      id="how-it-works"
      aria-labelledby="how-it-works-title"
    >
      <div className="container--wide">
        <Reveal as="div" className="section__head">
          <span className="eyebrow">Setup</span>
          <h2 className="h2" id="how-it-works-title">
            Three steps. <span className="muted">Once.</span>
          </h2>
        </Reveal>

        <ol className="steps">
          {steps.map((step, index) => (
            <Reveal
              as="li"
              key={step.title}
              delay={stagger(index)}
              className="tile"
            >
              <span className="step__num">
                {String(index + 1).padStart(2, "0")}
              </span>
              <h3>{step.title}</h3>
              <p>{step.body}</p>
            </Reveal>
          ))}
        </ol>
      </div>
    </section>
  );
}

const pillarTones = ["blue", "indigo", "green"] as const;

/** Two-up trust cards (privacy + open source) followed by the three security pillars. */
export function Security() {
  return (
    <section
      className="section section--tint"
      id="security"
      aria-labelledby="security-title"
    >
      <div className="container--wide">
        <Reveal as="div" className="section__head">
          <span className="eyebrow">Privacy &amp; security</span>
          <h2 className="h2" id="security-title">
            Built like it has to earn your trust.
          </h2>
        </Reveal>

        <div className="value-cards">
          {valueCards.map((card, index) => (
            <Reveal
              as="article"
              key={card.id}
              delay={stagger(index)}
              className={`value-card value-card--${card.tone}`}
            >
              <span className="value-card__glyph" aria-hidden="true">
                {card.icon}
              </span>
              <h3 className="value-card__headline">{card.headline}</h3>
              <p className="value-card__body">{card.body}</p>
              <a className="link-arrow" href={card.href} rel="noreferrer noopener">
                {card.linkLabel}
                <span className="link-arrow__chevron" aria-hidden="true">
                  ›
                </span>
              </a>
            </Reveal>
          ))}
        </div>

        <div className="pillar-row">
          {securityPillars.map((pillar, index) => (
            <Reveal
              as="div"
              key={pillar.title}
              delay={stagger(valueCards.length + index)}
              className="tile tile--outline pillar"
            >
              <span
                className={`pillar__glyph pillar__glyph--${pillarTones[index % pillarTones.length]}`}
              >
                {pillar.icon}
              </span>
              <h3>{pillar.title}</h3>
              <p>{pillar.body}</p>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}

/** Slim facts strip (License, Language, Platforms, Issues) + the Homebrew command. */
export function OpenSource() {
  return (
    <section
      className="section section--tint"
      id="open-source"
      aria-labelledby="open-source-title"
    >
      <div className="container--wide">
        <Reveal as="article" className="tile tile--outline facts-strip">
          {/* The facts speak for themselves visually — this heading exists for
              the accessibility tree and the h1 -> h2 -> h3 outline, same
              pattern as the Stats band's hidden heading above. */}
          <h2 className="visually-hidden" id="open-source-title">
            Open source facts
          </h2>

          <dl className="facts-strip__grid">
            <div className="facts-strip__item">
              <dt>License</dt>
              <dd>
                <a href={site.links.license} rel="noreferrer noopener">
                  MIT
                </a>
              </dd>
            </div>
            <div className="facts-strip__item">
              <dt>Language</dt>
              <dd>Swift 6 · SwiftUI</dd>
            </div>
            <div className="facts-strip__item">
              <dt>Platforms</dt>
              <dd>
                {site.minimumOS.ios} · {site.minimumOS.macos}
              </dd>
            </div>
            <div className="facts-strip__item">
              <dt>Issues</dt>
              <dd>
                <a href={site.links.issues} rel="noreferrer noopener">
                  Open a report
                </a>
              </dd>
            </div>
          </dl>

          <p className="small facts-strip__brew">
            <code className="opensource__brew">{site.homebrew.command}</code>
            {!site.homebrew.available && (
              <>
                {" "}
                <span className="opensource__brew-note">
                  — Homebrew cask, not published yet; see View on GitHub above.
                </span>
              </>
            )}
          </p>
        </Reveal>
      </div>
    </section>
  );
}

export function Faq() {
  return (
    <section className="section" id="faq" aria-labelledby="faq-title">
      <div className="container">
        <Reveal as="div" className="section__head">
          <span className="eyebrow">FAQ</span>
          <h2 className="h2" id="faq-title">
            Questions people actually ask.{" "}
            <span className="muted">Answered plainly.</span>
          </h2>
        </Reveal>

        <div className="grouped faq">
          {faqs.map((faq, index) => (
            <Reveal
              as="details"
              className="faq__item"
              key={faq.q}
              delay={stagger(index)}
            >
              <summary>
                <span>{faq.q}</span>
                <ChevronIcon className="faq__chevron" />
              </summary>
              <div className="faq__answer">
                <p>{faq.a}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}

/** Full-bleed gradient closing band (spec §10). */
export function FinalCta() {
  return (
    <section className="section cta cta--band" id="cta" aria-labelledby="cta-title">
      <div className="cta__highlight" aria-hidden="true" />
      <div className="container">
        <Reveal as="div" className="cta__inner">
          <h2 className="display" id="cta-title">
            Ready when you are.
          </h2>
          <p className="lede cta__lede">Free, open source, and yours to inspect.</p>
          <div className="actions">
            <a
              className="button button--light"
              href={site.links.latestRelease}
              rel="noreferrer noopener"
            >
              Download for Mac
            </a>
            <a
              className="link-arrow"
              href={site.links.iosWaitlist}
              rel="noreferrer noopener"
            >
              Join the iPhone waitlist
              <span className="link-arrow__chevron" aria-hidden="true">
                ›
              </span>
            </a>
          </div>
          <p className="cta__proof small">
            Free · MIT licensed · No accounts · Local Wi‑Fi only
          </p>
        </Reveal>
      </div>
    </section>
  );
}
