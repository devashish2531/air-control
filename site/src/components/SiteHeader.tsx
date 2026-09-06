"use client";

import { useEffect, useRef, useState } from "react";

import { Logo } from "@/components/Logo";
import { site } from "@/site.config";

const sections = [
  { href: "#features", label: "Features" },
  { href: "#how-it-works", label: "How it works" },
  { href: "#security", label: "Security" },
  { href: "#faq", label: "FAQ" },
];

/** Hamburger glyph on the mobile menu button: two bars that animate into an
 *  X via CSS transforms when `aria-expanded` flips (mobile design pass v18a
 *  — replaces the v4 chevron). Decorative — the button already carries
 *  `aria-label="Menu"`. */
function MenuIcon({ className }: { className?: string }) {
  return (
    <span className={className} aria-hidden="true">
      <span className="menu-button__bar menu-button__bar--top" />
      <span className="menu-button__bar menu-button__bar--bottom" />
    </span>
  );
}

export function SiteHeader() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const [activeHref, setActiveHref] = useState<string | null>(null);
  const menuButtonRef = useRef<HTMLButtonElement | null>(null);

  // Scroll-spy: the active link is whichever section is currently crossing
  // the "reading line" 40% down from the top / 55% up from the bottom.
  useEffect(() => {
    const ids = sections.map((item) => item.href.slice(1));
    const elements = ids
      .map((id) => document.getElementById(id))
      .filter((el): el is HTMLElement => el !== null);

    if (elements.length === 0 || typeof IntersectionObserver === "undefined") {
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setActiveHref(`#${entry.target.id}`);
          }
        }
      },
      { rootMargin: "-40% 0px -55% 0px" },
    );

    elements.forEach((el) => observer.observe(el));
    return () => observer.disconnect();
  }, []);

  // Passive, rAF-throttled scroll listener — only toggles a boolean, so one
  // frame of latency is invisible and this never competes with layout work.
  useEffect(() => {
    let ticking = false;

    const commit = () => {
      setScrolled(window.scrollY > 8);
      ticking = false;
    };

    const onScroll = () => {
      if (!ticking) {
        ticking = true;
        window.requestAnimationFrame(commit);
      }
    };

    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  // Escape closes the mobile panel and returns focus to the button that
  // opened it.
  useEffect(() => {
    if (!open) {
      return;
    }

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false);
        menuButtonRef.current?.focus();
      }
    };

    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [open]);

  // Lock body scroll while the panel is open; the cleanup always restores
  // it, including on unmount.
  useEffect(() => {
    if (!open) {
      return;
    }

    const root = document.documentElement;
    root.style.overflow = "hidden";
    return () => {
      root.style.overflow = "";
    };
  }, [open]);

  return (
    <header
      className="header"
      data-scrolled={scrolled ? "" : undefined}
      data-menu-open={open ? "" : undefined}
    >
      <div className="container header__inner">
        <a className="brand" href="#top">
          <Logo size={26} className="brand__logo" />
          <span className="brand__label">{site.name}</span>
        </a>

        <div className="header__right">
          <nav className="nav" aria-label="Primary">
            <ul className="nav__links">
              {sections.map((item) => (
                <li key={item.href}>
                  <a
                    href={item.href}
                    aria-current={activeHref === item.href ? "true" : undefined}
                  >
                    {item.label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>

          <a
            className="nav__github"
            href={site.links.github}
            rel="noreferrer noopener"
          >
            GitHub
          </a>

          {/* Two visually-identical pills, toggled by CSS `display` (mobile
              design pass v18a): under 48rem a phone visitor can't run a Mac
              installer, so the mobile pill routes to the on-page Download
              section (both platforms) instead of the Mac release asset. */}
          <a
            className="button button--primary button--small nav__download nav__download--desktop"
            href={site.links.latestRelease}
            rel="noreferrer noopener"
          >
            Download
          </a>
          <a
            className="button button--primary button--small nav__download nav__download--mobile"
            href="#download"
          >
            Download
          </a>

          <button
            type="button"
            className="menu-button"
            aria-label="Menu"
            aria-expanded={open}
            aria-controls="site-menu"
            onClick={() => setOpen((value) => !value)}
            ref={menuButtonRef}
          >
            <MenuIcon className="menu-button__icon" />
          </button>
        </div>
      </div>

      <div id="site-menu" className="menu-panel" hidden={!open}>
        <div className="container">
          <ul className="menu-panel__links">
            {sections.map((item) => (
              <li key={item.href}>
                <a
                  href={item.href}
                  aria-current={activeHref === item.href ? "true" : undefined}
                  onClick={() => setOpen(false)}
                >
                  {item.label}
                </a>
              </li>
            ))}
            <li>
              <a
                href={site.links.github}
                rel="noreferrer noopener"
                onClick={() => setOpen(false)}
              >
                GitHub
              </a>
            </li>
          </ul>
        </div>
      </div>
    </header>
  );
}
