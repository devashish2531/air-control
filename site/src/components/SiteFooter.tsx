import { site } from "@/site.config";

const links = [
  { href: site.links.github, label: "GitHub" },
  { href: site.links.releases, label: "Releases" },
  { href: site.links.license, label: "MIT License" },
  { href: site.links.security, label: "Security" },
  { href: site.links.contributing, label: "Contributing" },
  { href: site.links.protocol, label: "Protocol" },
];

export function SiteFooter() {
  return (
    <footer className="footer">
      <div className="container">
        <div className="footer__top">
          <p>
            <strong>{site.name}</strong> · {site.subline}
          </p>

          <ul className="footer__links">
            {links.map((link) => (
              <li key={link.href}>
                <a href={link.href} rel="noreferrer noopener">
                  {link.label}
                </a>
              </li>
            ))}
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
