"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type CSSProperties,
} from "react";

import { asset } from "@/lib/urls";
import { site } from "@/site.config";

const sections = [
  { href: "#features", label: "Features" },
  { href: "#how-it-works", label: "How it works" },
  { href: "#security", label: "Security" },
  { href: "#faq", label: "FAQ" },
];

/** GitHub mark, 18px (design spec v3 §B). Decorative — the link carries its
 *  own `aria-label`. */
function GithubIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      width="18"
      height="18"
      viewBox="0 0 16 16"
      fill="currentColor"
      aria-hidden="true"
      focusable="false"
    >
      <path
        fillRule="evenodd"
        clipRule="evenodd"
        d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"
      />
    </svg>
  );
}

/** Small download-arrow glyph shown before the "Download" label on wide
 *  screens (design spec v3 §B). Purely decorative — the button already has
 *  a text label. */
function DownloadArrowIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      width="14"
      height="14"
      viewBox="0 0 14 14"
      fill="none"
      aria-hidden="true"
      focusable="false"
    >
      <path
        d="M7 1.5v8M7 9.5 3.5 6M7 9.5 10.5 6"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path d="M2 11.5h10" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
    </svg>
  );
}

type IndicatorMetrics = { x: number; w: number };

export function SiteHeader() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const [activeHref, setActiveHref] = useState<string | null>(null);
  const [indicator, setIndicator] = useState<IndicatorMetrics | null>(null);
  const menuButtonRef = useRef<HTMLButtonElement | null>(null);
  const navRef = useRef<HTMLElement | null>(null);
  const linkRefs = useRef<Array<HTMLAnchorElement | null>>([]);
  // Read inside the resize listener without re-subscribing it on every
  // scroll-spy update — the listener itself never needs to change.
  const activeHrefRef = useRef<string | null>(null);
  useEffect(() => {
    activeHrefRef.current = activeHref;
  }, [activeHref]);

  const measureIndicator = useCallback(() => {
    const nav = navRef.current;
    const href = activeHrefRef.current;
    if (!nav || !href) {
      return;
    }
    const index = sections.findIndex((item) => item.href === href);
    const link = linkRefs.current[index];
    if (!link) {
      return;
    }
    const navRect = nav.getBoundingClientRect();
    const linkRect = link.getBoundingClientRect();
    setIndicator({ x: linkRect.left - navRect.left, w: linkRect.width });
  }, []);

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

  // Re-measure the indicator whenever the active section changes, and on
  // resize (rAF-throttled, same pattern as the scroll listener below) — never
  // on a per-frame basis, per the width-as-CSS-variable trade-off in
  // globals.css's .nav__indicator comment.
  useEffect(() => {
    measureIndicator();
  }, [activeHref, measureIndicator]);

  useEffect(() => {
    let ticking = false;
    const onResize = () => {
      if (!ticking) {
        ticking = true;
        window.requestAnimationFrame(() => {
          measureIndicator();
          ticking = false;
        });
      }
    };
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, [measureIndicator]);

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

  const indicatorStyle = indicator
    ? ({
        "--indicator-x": `${indicator.x}px`,
        "--indicator-w": `${indicator.w}px`,
      } as CSSProperties)
    : undefined;

  return (
    <header
      className="header"
      data-scrolled={scrolled ? "" : undefined}
      data-menu-open={open ? "" : undefined}
    >
      <div className="container header__pill">
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

        <nav className="nav" aria-label="Primary" ref={navRef}>
          <span
            className="nav__indicator"
            aria-hidden="true"
            data-visible={activeHref ? "" : undefined}
            style={indicatorStyle}
          />
          <ul className="nav__links">
            {sections.map((item, index) => (
              <li key={item.href}>
                <a
                  ref={(el) => {
                    linkRefs.current[index] = el;
                  }}
                  href={item.href}
                  aria-current={activeHref === item.href ? "true" : undefined}
                >
                  {item.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>

        <div className="nav__cta">
          <a
            className="nav__github"
            href={site.links.github}
            rel="noreferrer noopener"
            aria-label="GitHub"
          >
            <GithubIcon className="nav__github-icon" />
            <span className="nav__github-label" aria-hidden="true">
              GitHub
            </span>
          </a>

          <a
            className="button button--primary button--small nav__download"
            href={site.links.latestRelease}
            rel="noreferrer noopener"
          >
            <DownloadArrowIcon className="nav__download-icon" />
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

      <div
        className="menu-backdrop"
        hidden={!open}
        aria-hidden="true"
        onClick={() => setOpen(false)}
      />

      <div id="site-menu" className="menu-sheet" hidden={!open}>
        <div className="container menu-sheet__card">
          <ul className="menu-sheet__links">
            {sections.map((item, index) => (
              <li
                key={item.href}
                style={{ "--stagger-delay": `${index * 40}ms` } as CSSProperties}
              >
                <a href={item.href} onClick={() => setOpen(false)}>
                  {item.label}
                </a>
              </li>
            ))}
            <li
              style={
                { "--stagger-delay": `${sections.length * 40}ms` } as CSSProperties
              }
            >
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
