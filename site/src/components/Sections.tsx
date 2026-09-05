import { Reveal } from "@/components/Reveal";
import { faqs, features, securityPoints, steps } from "@/content";
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

export function Features() {
  return (
    <section className="section" id="features" aria-labelledby="features-title">
      <div className="container--wide">
        <Reveal as="div" className="section__head">
          <span className="eyebrow">Features</span>
          <h2 className="h2" id="features-title">
            Six ways to drive your Mac.{" "}
            <span className="muted">Every one in the box.</span>
          </h2>
          <p className="lede">
            Every mode is in the box. Nothing is behind a subscription, an
            account, or an upgrade prompt.
          </p>
        </Reveal>

        <div className="bento">
          {features.map((feature, index) => (
            <Reveal
              as="article"
              key={feature.id}
              delay={stagger(index)}
              className={
                feature.illustration ? "tile tile--wide" : "tile"
              }
            >
              <div className="tile__glyph">{feature.icon}</div>
              <h3>{feature.title}</h3>
              <p>{feature.body}</p>
              {feature.illustration && (
                <div className="tile__illustration" aria-hidden="true">
                  {feature.illustration}
                </div>
              )}
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
          <p className="lede">
            After the first pairing there is nothing to do: open the app and
            the cursor moves.
          </p>
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

        <Reveal as="div" className="tile stat" delay={stagger(steps.length)}>
          <div className="stat__lead">
            <p className="stat__value">&lt; 20&nbsp;ms</p>
            <p className="stat__caption">
              End-to-end motion latency, design target on 5&nbsp;GHz Wi‑Fi —
              the point where a remote pointer stops feeling remote.
            </p>
          </div>
          <p className="stat__note">
            That&rsquo;s a goal the project measures itself against, not a
            guarantee: your router, your channel and your distance from it all
            get a vote. The app ships a latency HUD so you can see the real
            number on your own network.
          </p>
        </Reveal>
      </div>
    </section>
  );
}

export function Security() {
  const [left, right] = [
    securityPoints.slice(0, Math.ceil(securityPoints.length / 2)),
    securityPoints.slice(Math.ceil(securityPoints.length / 2)),
  ];

  return (
    <section
      className="section band--dark"
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

        <div className="security__grid">
          {[left, right].map((column, columnIndex) => (
            <div className="grouped" key={columnIndex}>
              {column.map((point, index) => (
                <Reveal
                  as="div"
                  className="grouped__row security__row"
                  key={point.title}
                  delay={stagger(columnIndex * left.length + index)}
                >
                  <span className="security__glyph">{point.icon}</span>
                  <div>
                    <h3>{point.title}</h3>
                    <p>{point.body}</p>
                  </div>
                </Reveal>
              ))}
            </div>
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
              licensed, and public. Clone the repository and you can compile
              the exact thing you are running — and the protocol spec is
              written down so you can build your own client against it.
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
              <dt>Telemetry</dt>
              <dd>None collected</dd>
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
    <section className="section cta" id="cta" aria-labelledby="cta-title">
      <div className="container">
        <Reveal as="div" className="cta__inner">
          <h2 className="h2" id="cta-title">
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
