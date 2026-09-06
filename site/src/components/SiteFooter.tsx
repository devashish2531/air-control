import { Logo } from "@/components/Logo";
import { site } from "@/site.config";

// spec: DESIGN-SPEC.md footer redesign — Apple-quiet top (brand + link
// columns + legal text) over a full-bleed giant wordmark clipped by the
// page's bottom edge.

const productLinks = [
  { href: "#features", label: "Features" },
  { href: "#how-it-works", label: "How it works" },
  { href: "#security", label: "Security" },
  { href: "#faq", label: "FAQ" },
  { href: "#download", label: "Download" },
];

const projectLinks = [
  { href: site.links.github, label: "GitHub" },
  { href: site.links.releases, label: "Releases" },
  { href: site.links.contributing, label: "Contributing" },
  { href: site.links.protocol, label: "Protocol" },
  { href: site.links.security, label: "Security policy" },
];

export function SiteFooter() {
  return (
    <footer className="footer">
      <div className="container">
        <div className="footer__top">
          <div className="footer__brand">
            <Logo size={44} className="footer__logo" />
            <p className="footer__brand-name">{site.name}</p>
            <p className="footer__brand-tagline">
              Free and open source. Local Wi‑Fi only. No accounts.
            </p>
          </div>

          <nav className="footer__nav" aria-label="Footer">
            <div className="footer__col">
              <h2 className="footer__heading">Product</h2>
              <ul>
                {productLinks.map((link) => (
                  <li key={link.href}>
                    <a href={link.href}>{link.label}</a>
                  </li>
                ))}
              </ul>
            </div>

            <div className="footer__col">
              <h2 className="footer__heading">Project</h2>
              <ul>
                {projectLinks.map((link) => (
                  <li key={link.href}>
                    <a href={link.href} rel="noreferrer noopener">
                      {link.label}
                    </a>
                  </li>
                ))}
              </ul>
            </div>

            <div className="footer__col">
              <h2 className="footer__heading">Legal</h2>
              <ul>
                <li>
                  <a href={site.links.license} rel="noreferrer noopener">
                    MIT License
                  </a>
                </li>
                <li className="footer__note">No cookies · No analytics</li>
              </ul>
            </div>
          </nav>
        </div>

        <div className="footer__legal">
          <p>
            <strong>Privacy:</strong> this site sets no cookies, loads nothing
            from a third party and runs no analytics. The apps collect no data.
            There is no server to send it to.
          </p>
          <p>
            {site.name} is an independent open-source project and is not
            affiliated with, endorsed by, or sponsored by Apple Inc. Apple,
            iPhone, iPad, Mac and macOS are trademarks of Apple Inc.
          </p>
          <p>&copy; 2026 Air Control contributors · MIT License</p>
        </div>
      </div>

      <div className="footer__mark" aria-hidden="true">
        <div className="footer__mark-inner">
          <Logo size={64} className="footer__mark-logo" />
          <span>Air Control</span>
        </div>
      </div>
    </footer>
  );
}
