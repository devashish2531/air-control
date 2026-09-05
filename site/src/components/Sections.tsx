import { Reveal } from "@/components/Reveal";
import { faqs, features, securityPillars, stats, steps } from "@/content";
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
 * The landing page's centerpiece: three full-width alternating "spotlight"
 * rows (Touchpad, Air mouse, Keyboard) followed by a 3-up row of compact
 * cards (Presenter, Macros, iPad). `features` is ordered so the first three
 * entries are the spotlights and the rest are the compact cards.
 */
export function Spotlights() {
  const spotlightFeatures = features.slice(0, 3);
  const compactFeatures = features.slice(3);

  return (
    <section className="section" id="features" aria-labelledby="features-title">
      <div className="container--wide">
        <Reveal as="div" className="section__head">
          <span className="eyebrow">What it does</span>
          <h2 className="h2" id="features-title">
            One phone. <span className="muted">Every way to drive your Mac.</span>
          </h2>
        </Reveal>

        {spotlightFeatures.map((feature, index) => (
          <Reveal
            as="article"
            key={feature.id}
            delay={stagger(index)}
            className={
              index % 2 === 1 ? "spotlight-row spotlight-row--reverse" : "spotlight-row"
            }
          >
            <div className="spotlight-row__text">
              <span className="eyebrow spotlight-row__eyebrow">{feature.title}</span>
              <h3 className="spotlight-row__heading">{feature.headline}</h3>
              <p className="lede">{feature.benefit}</p>
            </div>
            <div className="spotlight-row__illustration" aria-hidden="true">
              {feature.illustration}
            </div>
          </Reveal>
        ))}

        <div className="tile-row">
          {compactFeatures.map((feature, index) => (
            <Reveal
              as="article"
              key={feature.id}
              delay={stagger(spotlightFeatures.length + index)}
              className="tile tile--outline"
            >
              <div className="tile__glyph">{feature.icon}</div>
              <h3>{feature.headline}</h3>
              <p>{feature.benefit}</p>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}

/** Full-bleed black band: four proof points as giant tabular numbers. */
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
            <Reveal as="li" key={step.title} delay={stagger(index)} className="tile">
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
            Your keystrokes never leave your network.{" "}
            <span className="muted">Everything else stays local too.</span>
          </h2>
          <p className="lede">
            An app that types for you and clicks for you has to earn that.
            Here is exactly how Air Control is built.
          </p>
        </Reveal>

        <div className="pillar-row">
          {securityPillars.map((pillar, index) => (
            <Reveal
              as="div"
              key={pillar.title}
              delay={stagger(index)}
              className="tile tile--outline pillar"
            >
              <span className="pillar__glyph">{pillar.icon}</span>
              <h3>{pillar.title}</h3>
              <p>{pillar.body}</p>
            </Reveal>
          ))}
        </div>

        <Reveal as="div" className="security__links" delay={300}>
          <p className="small">
            Full threat model and disclosure process:{" "}
            <a
              className="link-arrow"
              href={site.links.security}
              rel="noreferrer noopener"
            >
              SECURITY.md
              <span className="link-arrow__chevron" aria-hidden="true">
                ›
              </span>
            </a>
          </p>
          <p className="small">
            Wire format:{" "}
            <a
              className="link-arrow"
              href={site.links.protocol}
              rel="noreferrer noopener"
            >
              docs/protocol.md
              <span className="link-arrow__chevron" aria-hidden="true">
                ›
              </span>
            </a>
          </p>
        </Reveal>
      </div>
    </section>
  );
}

export function OpenSource() {
  return (
    <section
      className="section"
      id="open-source"
      aria-labelledby="open-source-title"
    >
      <div className="container--wide">
        <Reveal as="article" className="tile tile--wide opensource">
          <div className="opensource__copy">
            <span className="eyebrow">Open source</span>
            <h2 className="h2" id="open-source-title">
              Read it, build it. <span className="muted">Change it.</span>
            </h2>
            <p className="lede">
              Both apps and the shared protocol package are native Swift, MIT
              licensed, and public. Clone the repo, compile what you&rsquo;re
              running, or build your own client against the documented wire
              protocol.
            </p>
            <div className="actions">
              <a
                className="button button--primary"
                href={site.links.github}
                rel="noreferrer noopener"
              >
                View on GitHub
              </a>
              <a
                className="button button--secondary"
                href={site.links.contributing}
                rel="noreferrer noopener"
              >
                Contribute
              </a>
            </div>
            <p className="small">
              <code className="opensource__brew">{site.homebrew.command}</code>
              {!site.homebrew.available && (
                <>
                  {" "}
                  <span className="opensource__brew-note">
                    — Homebrew cask, not published yet; use the buttons above.
                  </span>
                </>
              )}
            </p>
          </div>

          <dl className="grouped facts">
            <div className="grouped__row">
              <dt>License</dt>
              <dd>
                <a href={site.links.license} rel="noreferrer noopener">
                  MIT
                </a>
              </dd>
            </div>
            <div className="grouped__row">
              <dt>Language</dt>
              <dd>Swift 6 · SwiftUI</dd>
            </div>
            <div className="grouped__row">
              <dt>Platforms</dt>
              <dd>
                {site.minimumOS.ios} · {site.minimumOS.macos}
              </dd>
            </div>
            <div className="grouped__row">
              <dt>Issues</dt>
              <dd>
                <a href={site.links.issues} rel="noreferrer noopener">
                  Open a report
                </a>
              </dd>
            </div>
          </dl>
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

export function FinalCta() {
  return (
    <section className="section cta section--tint" id="cta" aria-labelledby="cta-title">
      <div className="container">
        <Reveal as="div" className="cta__inner">
          <h2 className="display" id="cta-title">
            Ready <span className="muted">when you are.</span>
          </h2>
          <p className="lede">Free, open source, and yours to inspect.</p>
          <div className="actions">
            <a
              className="button button--primary"
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
          <p className="cta__proof small muted">
            Free · MIT licensed · No accounts · Local Wi‑Fi only
          </p>
        </Reveal>
      </div>
    </section>
  );
}
