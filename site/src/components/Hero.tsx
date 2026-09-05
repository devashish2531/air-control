import { asset } from "@/lib/urls";
import { site } from "@/site.config";

export function Hero() {
  return (
    <section className="hero" id="top">
      <div className="container hero__inner">
        <div>
          <h1 className="hero__title">{site.name}</h1>

          <p className="hero__promise">{site.tagline}.</p>

          <div className="hero__actions">
            <a
              className="button button--primary"
              href={site.links.latestRelease}
              rel="noreferrer noopener"
            >
              Download for Mac
            </a>

            <a
              className="button button--secondary"
              href={site.links.iosWaitlist}
              rel="noreferrer noopener"
            >
              Get for iPhone
              <span className="badge">Coming soon</span>
            </a>
          </div>

          <p className="hero__subline">{site.subline}</p>

          <div className="hero__brew">
            <code className="codeblock">{site.homebrew.command}</code>
            <p className="note">
              {site.homebrew.available
                ? "Homebrew cask."
                : "Homebrew cask — not published yet; use the download button above."}
            </p>
          </div>
        </div>

        {/*
          Plain <img>: the export is unoptimized, so next/image would only add
          client JavaScript and, worse, emits a src without the basePath.
          Explicit width/height keeps cumulative layout shift at zero. Both PNGs
          come from design/icons via site/scripts/make-assets.sh.
        */}
        <div className="hero__icons">
          <img
            className="hero__icon hero__icon--ios"
            src={asset("/icon-ios.png")}
            alt="The Air Control app icon for iPhone and iPad"
            width={384}
            height={384}
            decoding="async"
            fetchPriority="high"
          />
          <img
            className="hero__icon hero__icon--mac"
            src={asset("/icon-mac.png")}
            alt="The Air Control menu-bar helper icon for macOS"
            width={384}
            height={384}
            decoding="async"
            fetchPriority="high"
          />
        </div>
      </div>
    </section>
  );
}
