import { asset } from "@/lib/urls";
import { site } from "@/site.config";

const sections = [
  { href: "#features", label: "Features" },
  { href: "#how-it-works", label: "How it works" },
  { href: "#security", label: "Security" },
  { href: "#faq", label: "FAQ" },
];

export function SiteHeader() {
  return (
    <header className="header">
      <div className="container header__inner">
        <a className="brand" href="#top">
          {/* Decorative: the brand name follows in text. */}
          <img
            src={asset("/icon-ios.png")}
            alt=""
            width={28}
            height={28}
            decoding="async"
          />
          {site.name}
        </a>

        <nav className="nav" aria-label="Primary">
          {sections.map((item) => (
            <a key={item.href} className="nav__section" href={item.href}>
              {item.label}
            </a>
          ))}
          <a href={site.links.github} rel="noreferrer noopener">
            GitHub
          </a>
        </nav>
      </div>
    </header>
  );
}
