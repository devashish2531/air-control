"use client";

import { useRef, useState, useSyncExternalStore, type KeyboardEvent } from "react";

import { CardStrip } from "@/components/CardStrip";
import { Reveal } from "@/components/Reveal";
import { asset } from "@/lib/urls";

type Theme = "light" | "dark";

type Shot = {
  slug: string;
  /** Base alt text (carries the screen name); "in light/dark mode" is appended per image. */
  alt: string;
};

/**
 * Six screens, in the same order as the Features strip (Touchpad, Air pointer,
 * Keyboard, Remote, Macros, Settings). Screenshot files live in
 * `public/screenshots/<slug>-<light|dark>-<480|960>.png` — see
 * `scripts/make-screenshots.sh`.
 */
const shots: Shot[] = [
  { slug: "touchpad", alt: "Touchpad screen" },
  { slug: "air-pointer", alt: "Air Pointer screen" },
  { slug: "keyboard", alt: "Keyboard screen" },
  { slug: "remote", alt: "Remote screen" },
  { slug: "macros", alt: "Macros screen" },
  { slug: "settings", alt: "Settings screen" },
];

/** 480x1043 at the source's 1206x2622 aspect ratio (see make-screenshots.sh). */
const SCREEN_WIDTH = 480;
const SCREEN_HEIGHT = 1043;

/**
 * One of the two stacked images inside a `.shot__screen`. Both light and dark
 * captures are always in the DOM (so the crossfade never has to fetch on
 * toggle) — the inactive one is `opacity: 0` and `aria-hidden`.
 */
function ShotImage({
  slug,
  mode,
  alt,
  active,
  eager,
}: {
  slug: string;
  mode: Theme;
  alt: string;
  active: boolean;
  eager: boolean;
}) {
  const src480 = asset(`/screenshots/${slug}-${mode}-480.png`);
  const src960 = asset(`/screenshots/${slug}-${mode}-960.png`);

  return (
    <img
      className={active ? "shot__img is-active" : "shot__img"}
      aria-hidden={!active}
      src={src960}
      srcSet={`${src480} 480w, ${src960} 960w`}
      sizes="(min-width: 64rem) 300px, (min-width: 40rem) 44vw, 78vw"
      width={SCREEN_WIDTH}
      height={SCREEN_HEIGHT}
      loading={eager ? "eager" : "lazy"}
      decoding="async"
      alt={`${alt} in ${mode} mode`}
    />
  );
}

function ShotCard({ shot, theme, eager }: { shot: Shot; theme: Theme; eager: boolean }) {
  return (
    <article className="shot">
      <div className="shot__frame">
        <div className="shot__screen">
          <span className="shot__island" aria-hidden="true" />
          <ShotImage
            slug={shot.slug}
            mode="light"
            alt={shot.alt}
            active={theme === "light"}
            eager={eager}
          />
          <ShotImage
            slug={shot.slug}
            mode="dark"
            alt={shot.alt}
            active={theme === "dark"}
            eager={eager}
          />
        </div>
      </div>
    </article>
  );
}

/**
 * iOS-style two-segment control ("Light" / "Dark") driving which screenshot
 * of each card is visible. `role="radiogroup"` of two `role="radio"` buttons
 * (ARIA APG radio-group pattern): a roving `tabIndex` keeps only the checked
 * segment tabbable, and the arrow keys move both the check and focus.
 */
function Segmented({
  theme,
  onChange,
}: {
  theme: Theme;
  onChange: (theme: Theme) => void;
}) {
  const lightRef = useRef<HTMLButtonElement | null>(null);
  const darkRef = useRef<HTMLButtonElement | null>(null);

  const select = (next: Theme) => {
    onChange(next);
    (next === "light" ? lightRef : darkRef).current?.focus();
  };

  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (
      event.key === "ArrowLeft" ||
      event.key === "ArrowUp" ||
      event.key === "ArrowRight" ||
      event.key === "ArrowDown"
    ) {
      event.preventDefault();
      select(theme === "light" ? "dark" : "light");
    }
  };

  return (
    <div
      className="seg"
      data-selected={theme}
      role="radiogroup"
      aria-label="Appearance"
      onKeyDown={onKeyDown}
    >
      <span className="seg__thumb" aria-hidden="true" />
      <button
        type="button"
        role="radio"
        aria-checked={theme === "light"}
        tabIndex={theme === "light" ? 0 : -1}
        className="seg__btn"
        ref={lightRef}
        onClick={() => select("light")}
      >
        Light
      </button>
      <button
        type="button"
        role="radio"
        aria-checked={theme === "dark"}
        tabIndex={theme === "dark" ? 0 : -1}
        className="seg__btn"
        ref={darkRef}
        onClick={() => select("dark")}
      >
        Dark
      </button>
    </div>
  );
}

/**
 * `prefers-color-scheme: dark` as a `useSyncExternalStore` source rather than
 * `useState` + effect: the snapshot differs between server (always "light",
 * via `getServerSnapshot`) and client, and syncing that through a manual
 * `useEffect(() => setState(...), [])` trips the "no setState synchronously
 * in an effect" lint rule (react-hooks) for exactly the reason it exists —
 * it's a two-render cascade. `useSyncExternalStore` is React's sanctioned
 * escape hatch for a value that lives outside React (here, the OS setting)
 * and needs a server/client-safe initial snapshot.
 */
function subscribeToColorScheme(onChange: () => void) {
  const mql = window.matchMedia("(prefers-color-scheme: dark)");
  mql.addEventListener("change", onChange);
  return () => mql.removeEventListener("change", onChange);
}

function getColorSchemeSnapshot(): boolean {
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}

function getColorSchemeServerSnapshot(): boolean {
  return false;
}

/**
 * "A look inside" — six-card screenshot strip (reuses `CardStrip`, spec A)
 * with a Light/Dark segmented control swapping every card's visible capture
 * at once. Rendered light by default (SSR-safe, matches the rest of the
 * page's "light-only chrome" stance); once hydrated, it starts on Dark if
 * the OS is already in dark mode — until the visitor taps the segmented
 * control, which then overrides the OS reading.
 */
export function Gallery() {
  const systemPrefersDark = useSyncExternalStore(
    subscribeToColorScheme,
    getColorSchemeSnapshot,
    getColorSchemeServerSnapshot,
  );
  const [override, setOverride] = useState<Theme | null>(null);
  const theme: Theme = override ?? (systemPrefersDark ? "dark" : "light");

  return (
    <section className="section" id="gallery" aria-labelledby="gallery-title">
      <Reveal as="div" className="container--wide gallery__top">
        <div className="section__head">
          <span className="eyebrow">A look inside</span>
          <h2 className="h2" id="gallery-title">
            Every mode, <span className="muted">in light or dark.</span>
          </h2>
        </div>

        <Segmented theme={theme} onChange={setOverride} />
      </Reveal>

      <Reveal as="div" delay={60}>
        <CardStrip ariaLabel="App screenshots">
          {shots.map((shot, index) => (
            <ShotCard key={shot.slug} shot={shot} theme={theme} eager={index < 2} />
          ))}
        </CardStrip>
      </Reveal>
    </section>
  );
}
