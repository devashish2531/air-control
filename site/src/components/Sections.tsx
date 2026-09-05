import { faqs, features, securityPoints, steps } from "@/content";
import { site } from "@/site.config";

export function Features() {
  return (
    <section className="section" id="features" aria-labelledby="features-title">
      <div className="container">
        <div className="section__head">
          <span className="section__eyebrow">Features</span>
          <h2 className="section__title" id="features-title">
            Six ways to drive your Mac from the couch
          </h2>
          <p className="section__lede">
            Every mode is in the box. Nothing is behind a subscription, an
            account, or an upgrade prompt.
          </p>
        </div>

        <div className="grid">
          {features.map((feature) => (
            <article className="card" key={feature.id}>
              <span className="card__icon">{feature.icon}</span>
              <h3 className="card__title">{feature.title}</h3>
              <p className="card__body">{feature.body}</p>
            </article>
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
      <div className="container">
        <div className="section__head">
          <span className="section__eyebrow">How it works</span>
          <h2 className="section__title" id="how-it-works-title">
            Three steps, once
          </h2>
          <p className="section__lede">
            After the first pairing there is nothing to do: open the app and the
            cursor moves.
          </p>
        </div>

        <ol className="steps">
          {steps.map((step) => (
            <li key={step.title}>
              <h3 className="card__title">{step.title}</h3>
              <p className="card__body">{step.body}</p>
            </li>
          ))}
        </ol>

        <p className="note note--afterGrid">
          Air Control is built to a design target of{" "}
          <strong>under 20&nbsp;ms</strong> end-to-end motion latency on 5&nbsp;GHz
          Wi‑Fi — the point where a remote pointer stops feeling remote. That is
          a goal the project measures itself against, not a guarantee: your
          router, your channel and your distance from it all get a vote. The app
          ships a latency HUD so you can see the real number on your own network.
        </p>
      </div>
    </section>
  );
}

export function Security() {
  return (
    <section
      className="section section--security"
      id="security"
      aria-labelledby="security-title"
    >
      <div className="container">
        <div className="section__head">
          <span className="section__eyebrow">Security</span>
          <h2 className="section__title" id="security-title">
            Your keystrokes never leave your network
          </h2>
          <p className="section__lede">
            An app that types for you and clicks for you has to earn that. Here
            is exactly how Air Control is built.
          </p>
        </div>

        <ul className="security__list">
          {securityPoints.map((point) => (
            <li className="security__item" key={point.title}>
              <h3>{point.title}</h3>
              <p>{point.body}</p>
            </li>
          ))}
        </ul>

        <p className="note note--afterList">
          Full threat model and disclosure process:{" "}
          <a href={site.links.security} rel="noreferrer noopener">
            SECURITY.md
          </a>{" "}
          · wire format:{" "}
          <a href={site.links.protocol} rel="noreferrer noopener">
            docs/protocol.md
          </a>
        </p>
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
      <div className="container">
        <div className="opensource">
          <div>
            <span className="section__eyebrow">Open source</span>
            <h2 className="section__title" id="open-source-title">
              Read it, build it, change it
            </h2>
            <p className="section__lede">
              Both apps and the shared protocol package are native Swift, MIT
              licensed, and public. Clone the repository and you can compile the
              exact thing you are running — and the protocol spec is written down
              so you can build your own client against it.
            </p>
            <div className="hero__actions">
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

          <dl className="opensource__facts">
            <div>
              <dt>License</dt>
              <dd>
                <a href={site.links.license} rel="noreferrer noopener">
                  MIT
                </a>
              </dd>
            </div>
            <div>
              <dt>Language</dt>
              <dd>Swift 6 · SwiftUI</dd>
            </div>
            <div>
              <dt>Platforms</dt>
              <dd>
                {site.minimumOS.ios} · {site.minimumOS.macos}
              </dd>
            </div>
            <div>
              <dt>Telemetry</dt>
              <dd>None collected</dd>
            </div>
            <div>
              <dt>Issues</dt>
              <dd>
                <a href={site.links.issues} rel="noreferrer noopener">
                  Open a report
                </a>
              </dd>
            </div>
          </dl>
        </div>
      </div>
    </section>
  );
}

export function Faq() {
  return (
    <section className="section" id="faq" aria-labelledby="faq-title">
      <div className="container">
        <div className="section__head">
          <span className="section__eyebrow">FAQ</span>
          <h2 className="section__title" id="faq-title">
            Questions people actually ask
          </h2>
        </div>

        <div className="faq">
          {faqs.map((faq) => (
            <details key={faq.q}>
              <summary>{faq.q}</summary>
              <p>{faq.a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
