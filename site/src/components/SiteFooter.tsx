import { site } from "@/site.config";

export function SiteFooter() {
  return (
    <footer className="footer">
      <div className="container">
        <div className="footer__top">
          <p>
            <strong>{site.name}</strong> · {site.subline}
          </p>

          <ul className="footer__links">
            <li>
              <a href={site.links.github} rel="noreferrer noopener">
                GitHub
              </a>
            </li>
            <li>
              <a href={site.links.license} rel="noreferrer noopener">
                MIT License
              </a>
            </li>
            <li>
              <a href={site.links.security} rel="noreferrer noopener">
                Security
              </a>
            </li>
            <li>
              <a href={site.links.contributing} rel="noreferrer noopener">
                Contributing
              </a>
            </li>
            <li>
              <a href={site.links.releases} rel="noreferrer noopener">
                Releases
              </a>
            </li>
          </ul>
        </div>

        <div className="footer__legal">
          <p>
            <strong>Privacy:</strong> this site sets no cookies, loads nothing
            from a third party and runs no analytics. The apps collect no data —
            there is no server to send it to.
          </p>
          <p>
            {site.name} is an independent open-source project and is not
            affiliated with, endorsed by, or sponsored by Apple Inc. Apple,
            iPhone, iPad, Mac and macOS are trademarks of Apple Inc.
          </p>
        </div>
      </div>
    </footer>
  );
}
