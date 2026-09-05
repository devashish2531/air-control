"use client";

import { useEffect, useRef, useState } from "react";

import { asset } from "@/lib/urls";
import { site } from "@/site.config";

const sections = [
  { href: "#features", label: "Features" },
  { href: "#how-it-works", label: "How it works" },
  { href: "#security", label: "Security" },
  { href: "#faq", label: "FAQ" },
];

export function SiteHeader() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const menuButtonRef = useRef<HTMLButtonElement | null>(null);

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

  // Escape closes the mobile sheet and returns focus to the button that
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

  // Lock body scroll while the sheet is open; the cleanup always restores it,
  // including on unmount.
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
    <header className="header" data-scrolled={scrolled ? "" : undefined}>
      <div className="container header__inner">
        <a className="brand" href="#top">
          <img
            src={asset("/icon-ios-64.png")}
            alt=""
            width={22}
            height={22}
            decoding="async"
          />
          <span className="brand__label">{site.name}</span>
        </a>

        <nav className="nav" aria-label="Primary">
          <ul className="nav__links">
            {sections.map((item) => (
              <li key={item.href}>
                <a href={item.href}>{item.label}</a>
              </li>
            ))}
          </ul>
        </nav>

        <div className="nav__cta">
          <a
            className="button button--primary button--small"
            href={site.links.latestRelease}
            rel="noreferrer noopener"
          >
            Download
          </a>
          <a className="nav__github" href={site.links.github} rel="noreferrer noopener">
            GitHub
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
            <svg
              width="20"
              height="20"
              viewBox="0 0 20 20"
              aria-hidden="true"
              focusable="false"
            >
              <line
                className="menu-button__bar menu-button__bar--top"
                x1="2"
                y1="6"
                x2="18"
                y2="6"
              />
              <line
                className="menu-button__bar menu-button__bar--bottom"
                x1="2"
                y1="14"
                x2="18"
                y2="14"
              />
            </svg>
          </button>
        </div>
      </div>

      <div id="site-menu" className="menu-sheet" hidden={!open}>
        <ul className="menu-sheet__links">
          {sections.map((item) => (
            <li key={item.href}>
              <a href={item.href} onClick={() => setOpen(false)}>
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
    </header>
  );
}
