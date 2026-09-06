"use client";

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";

/**
 * Must match the `gap` on `.strip` in sections.css — used to compute how far
 * one "page" of cards is when the nav buttons are pressed (spec A).
 */
const STRIP_GAP_PX = 20;

function ChevronIcon({ direction }: { direction: "prev" | "next" }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d={direction === "prev" ? "M14 6l-6 6 6 6" : "M10 6l6 6-6 6"} />
    </svg>
  );
}

function prefersReducedMotion(): boolean {
  return (
    typeof window !== "undefined" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
  );
}

/**
 * Client wrapper around the feature card strip (spec A). Owns the track ref,
 * the prev/next buttons and their disabled-at-the-ends state — the cards
 * themselves are server-rendered `children` so the feature copy stays in the
 * initial HTML for SEO, matching the `Reveal` composition pattern.
 */
export function CardStrip({ children }: { children: ReactNode }) {
  const trackRef = useRef<HTMLDivElement | null>(null);
  const rafRef = useRef<number | null>(null);
  const [atStart, setAtStart] = useState(true);
  const [atEnd, setAtEnd] = useState(false);

  const updateEdges = useCallback(() => {
    const track = trackRef.current;
    if (!track) {
      return;
    }
    const maxScroll = track.scrollWidth - track.clientWidth;
    setAtStart(track.scrollLeft <= 1);
    setAtEnd(track.scrollLeft >= maxScroll - 1);
  }, []);

  // rAF-throttled: scroll fires far more often than once per frame.
  const scheduleUpdate = useCallback(() => {
    if (rafRef.current !== null) {
      return;
    }
    rafRef.current = requestAnimationFrame(() => {
      rafRef.current = null;
      updateEdges();
    });
  }, [updateEdges]);

  useEffect(() => {
    updateEdges();
    const track = trackRef.current;
    if (!track) {
      return;
    }
    track.addEventListener("scroll", scheduleUpdate, { passive: true });
    window.addEventListener("resize", scheduleUpdate);
    return () => {
      track.removeEventListener("scroll", scheduleUpdate);
      window.removeEventListener("resize", scheduleUpdate);
      if (rafRef.current !== null) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [scheduleUpdate, updateEdges]);

  const scrollByPage = useCallback((direction: 1 | -1) => {
    const track = trackRef.current;
    const firstCard = track?.firstElementChild as HTMLElement | null | undefined;
    if (!track || !firstCard) {
      return;
    }
    const cardWidth = firstCard.getBoundingClientRect().width;
    const step = cardWidth + STRIP_GAP_PX;
    const visibleCount = Math.max(1, Math.round(track.clientWidth / step));
    track.scrollBy({
      left: direction * step * visibleCount,
      behavior: prefersReducedMotion() ? "auto" : "smooth",
    });
  }, []);

  return (
    <div className="strip-shell">
      <div
        className="strip"
        ref={trackRef}
        role="region"
        aria-label="Feature cards"
        tabIndex={0}
      >
        {children}
      </div>

      <div className="strip-nav">
        <button
          type="button"
          className="strip-nav__btn"
          aria-label="Previous cards"
          aria-disabled={atStart}
          onClick={() => {
            if (!atStart) {
              scrollByPage(-1);
            }
          }}
        >
          <ChevronIcon direction="prev" />
        </button>
        <button
          type="button"
          className="strip-nav__btn"
          aria-label="Next cards"
          aria-disabled={atEnd}
          onClick={() => {
            if (!atEnd) {
              scrollByPage(1);
            }
          }}
        >
          <ChevronIcon direction="next" />
        </button>
      </div>
    </div>
  );
}
