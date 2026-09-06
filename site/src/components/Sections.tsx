import { CardStrip } from "@/components/CardStrip";
import { DownloadQR } from "@/components/DownloadQR";
import { Reveal } from "@/components/Reveal";
import {
  devices,
  faqs,
  features,
  stats,
  steps,
  trustCards,
  type Feature,
  type TrustCard,
} from "@/content";
import { site } from "@/site.config";

/** Stagger delay for the Nth sibling in a revealed group, capped per spec (~300ms). */
function stagger(index: number): number {
  return Math.min(index * 60, 300);
}

/** Downward chevron — used inside the FAQ's round affordance button, which
 * itself rotates 180° on open (see `.faq__chevron-btn` in sections.css), so
 * the glyph reads "collapsed, pointing down" -> "open, pointing up". */
function ChevronIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      width="14"
      height="14"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M6 9l6 6 6-6" />
    </svg>
  );
}

/** 22px stroke icon for the Download section's two device cards. */
function MacGlyphIcon() {
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
      <rect x="2.5" y="4" width="19" height="12.5" rx="1.8" />
      <path d="M8 20h8M12 16.5V20" />
    </svg>
  );
}

function IPhoneGlyphIcon() {
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
      <rect x="6.5" y="2.5" width="11" height="19" rx="2.5" />
      <path d="M10.5 18.2h3" />
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
        <Reveal as="div" className="section__head">
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

/**
 * One card in the security trust row: 40px coloured line icon, then a
 * single bold statement whose lead phrase is coloured (DESIGN-SPEC-v7).
 * Server-rendered — `CardStrip` only owns the scroll mechanics.
 */
function TrustCardArticle({ card }: { card: TrustCard }) {
  return (
    <article className={`trust-card trust-card--${card.tone}`}>
      <span className="trust-card__icon" aria-hidden="true">
        {card.icon}
      </span>
      <p className="trust-card__text">
        <span className="trust-card__lead">{card.lead}</span> {card.rest}
      </p>
    </article>
  );
}

/**
 * Apple Store "difference row" style trust strip (DESIGN-SPEC-v7): a left-
 * aligned head with no lede, then one `CardStrip` row of five short
 * statement cards, then a plain links line to the full threat model and
 * wire protocol docs. Replaces the old two value cards + three pillar row.
 */
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
            Built like it has to earn your trust.{" "}
            <span className="muted">Here&rsquo;s how.</span>
          </h2>
        </Reveal>
      </div>

      <Reveal as="div">
        <CardStrip ariaLabel="Security highlights">
          {trustCards.map((card) => (
            <TrustCardArticle card={card} key={card.id} />
          ))}
        </CardStrip>
      </Reveal>

      <div className="container--wide">
        <p className="small trust-links">
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
          {" · "}
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
      </div>
    </section>
  );
}

/**
 * Get Air Control: two equal device cards (Mac / iPhone & iPad), then a
 * single centered license line (`id="open-source"`, spec C2). Replaces the
 * old slim facts strip + Homebrew line entirely.
 */
export function Download() {
  return (
    <section className="section" id="download" aria-labelledby="download-title">
      <div className="container--wide">
        <Reveal as="div" className="section__head">
          <span className="eyebrow">Get Air Control</span>
          <h2 className="h2" id="download-title">
            Free on both ends. <span className="muted">Nothing to sign up for.</span>
          </h2>
        </Reveal>

        <div className="download-cards">
          <Reveal as="article" className="download-card" delay={stagger(0)}>
            <span className="download-card__icon glass" aria-hidden="true">
              <MacGlyphIcon />
            </span>
            <h3 className="download-card__title">Air Control for Mac</h3>
            <p className="small download-card__requirement">
              Menu-bar helper · {site.minimumOS.macos} or later
            </p>
            <div className="download-card__body">
              <a
                className="button button--primary"
                href={site.links.latestRelease}
                rel="noreferrer noopener"
              >
                Download for Mac
              </a>
              <div className="download-card__brew">
                <code
                  className="download-card__brew-code"
                  title={site.homebrew.command}
                >
                  {site.homebrew.command}
                </code>
                {!site.homebrew.available && (
                  <p className="small download-card__brew-note">
                    Homebrew cask not published yet
                  </p>
                )}
              </div>
            </div>
          </Reveal>

          <Reveal as="article" className="download-card" delay={stagger(1)}>
            <span className="download-card__icon glass" aria-hidden="true">
              <IPhoneGlyphIcon />
            </span>
            <h3 className="download-card__title">Air Control for iPhone &amp; iPad</h3>
            <p className="small download-card__requirement">
              {site.minimumOS.ios} or later
            </p>
            <div className="download-card__body">
              <div className="download-card__qr-row">
                <DownloadQR size={96} />
                <div className="download-card__qr-text">
                  <p className="download-card__qr-caption">
                    Scan to open this page on your phone
                  </p>
                  <p className="small download-card__qr-subcaption">
                    Join the waitlist to hear when it ships
                  </p>
                </div>
              </div>
              <div className="actions">
                <a
                  className="button button--secondary"
                  href={site.links.iosWaitlist}
                  rel="noreferrer noopener"
                >
                  Join the waitlist
                </a>
                <span className="badge">Coming soon</span>
              </div>
            </div>
          </Reveal>
        </div>

        <Reveal as="p" className="small download-license" id="open-source">
          <a href={site.links.license} rel="noreferrer noopener">
            MIT licensed
          </a>
          {" · "}
          <span>Swift 6 · SwiftUI</span>
          {" · "}
          <a className="link-arrow" href={site.links.github} rel="noreferrer noopener">
            Source on GitHub
            <span className="link-arrow__chevron" aria-hidden="true">
              ›
            </span>
          </a>
          {" · "}
          <a className="link-arrow" href={site.links.issues} rel="noreferrer noopener">
            Report an issue
            <span className="link-arrow__chevron" aria-hidden="true">
              ›
            </span>
          </a>
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

        <div className="faq-panel faq">
          {faqs.map((faq, index) => (
            <Reveal
              as="details"
              className="faq__item"
              key={faq.q}
              delay={stagger(index)}
            >
              <summary>
                <span className="faq__question">{faq.q}</span>
                <span className="faq__chevron-btn" aria-hidden="true">
                  <ChevronIcon className="faq__chevron" />
                </span>
              </summary>
              <div className="faq__answer">
                <p>{faq.a}</p>
              </div>
            </Reveal>
          ))}
        </div>

        <Reveal as="p" className="faq-more" delay={stagger(faqs.length)}>
          <a className="link-arrow" href={site.links.issues} rel="noreferrer noopener">
            Still have a question? Open an issue
            <span className="link-arrow__chevron" aria-hidden="true">
              ›
            </span>
          </a>
        </Reveal>
      </div>
    </section>
  );
}

/** Closing card in the page's own light language — `--bg-secondary` panel,
 * 1px separator border, no glows (spec v13 §E). Replaces the v8 dark
 * "Security Bounty"-style card. */
export function FinalCta() {
  return (
    <section className="section cta" id="cta" aria-labelledby="cta-title">
      <div className="container container--wide">
        <Reveal as="div" className="cta-card">
          <div className="cta-card__copy">
            <span className="eyebrow cta-card__eyebrow">Get Air Control</span>
            <h2 className="cta-card__title" id="cta-title">
              Ready when <span className="grad-text grad-text--cta">you are.</span>
            </h2>
            <p className="lede cta-card__lede">
              Free, open source, and yours to inspect. Nothing to sign up for.
            </p>
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
            <p className="cta-card__proof small">
              Free · MIT licensed · No accounts · Local Wi‑Fi only
            </p>
          </div>
          <div className="cta-card__stack" aria-hidden="true">
            iOS
            <br />
            iPadOS
            <br />
            macOS
          </div>
        </Reveal>
      </div>
    </section>
  );
}
