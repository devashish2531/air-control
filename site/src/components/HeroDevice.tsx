import { Reveal } from "@/components/Reveal";
import { asset } from "@/lib/urls";

/**
 * Hero spec §D (DESIGN-SPEC-v13.md "D. Hero"): an iPhone-Pro-style phone
 * (titanium frame, black bezel, continuous corners, side buttons, a real
 * dynamic island overlay) overlapping the lower-left of a MacBook-Pro-style
 * display (notch, aluminium base, Sequoia-like wallpaper, menu bar, Finder
 * window, Dock) with an animated cursor/finger pair, plus a "Wi‑Fi signal"
 * burst (owner feedback: "overlapping Wi‑Fi signal animations, larger, at
 * the MacBook's bottom-right corner") at the MacBook's bottom-right corner,
 * tilted toward the devices. Mostly CSS/SVG — no JS — except the phone's
 * screen, which is the real Touchpad screenshot
 * (`public/screenshots/touchpad-light-*.png`) rather than a mocked-up UI,
 * so it reads as the actual app; layout, proportions and motion still live
 * in hero.css. The finger + cursor + a Finder grid-tile flash loop the same
 * 6s timeline (see hero.css "Loops"); the signal burst and the menu-bar
 * Wi‑Fi glyph loop independently (hero.css "Wi‑Fi signal bursts").
 *
 * The whole illustration is decorative (aria-hidden); the visually-hidden
 * paragraph below it is the accessible description.
 *
 * `.mac-parallax` / `.phone-parallax` (DESIGN-SPEC-v6.md §B.4) are plain
 * placement wrappers: they own the absolute positioning + `--mac-w`/
 * `--phone-w` that `.mac`/`.phone` used to carry themselves, so the
 * scroll-driven `animation-timeline: view()` parallax can live on the
 * wrapper while `.mac`/`.phone` stay free for their own entrance animation
 * (hero.css) — no element ends up with two animations at once.
 */

/** Seven Dock tiles (spec B) — colours live in hero.css as
 * `.mac__dock-tile:nth-child(n)` rules, not inline styles. */
const DOCK_TILE_COUNT = 7;

/** The three concentric arc paths from Logo.tsx's mark, reused verbatim
 * (same 64x64 grid) for the hero's "Wi‑Fi signal" burst (owner feedback:
 * "overlapping Wi‑Fi signal animations") at the MacBook's bottom-right
 * corner. */
const SIGNAL_ARC_PATHS: ReadonlyArray<string> = [
  "M25.11 20.22A9 9 0 0 1 32 17a9 9 0 0 1 6.89 3.22",
  "M19.74 15.72A16 16 0 0 1 32 10a16 16 0 0 1 12.26 5.72",
  "M14.38 11.22A23 23 0 0 1 32 3a23 23 0 0 1 17.62 8.22",
];

/**
 * The Wi‑Fi signal burst: the three signal arcs (opacity-pulsed in sequence)
 * plus two expanding ripple rings, sharing one origin. Purely decorative —
 * the parent `.signals` wrapper carries `aria-hidden`. Positioned via the
 * `signal--mac` modifier class (hero.css); every other visual property
 * lives there too, nothing inline.
 */
function SignalBurst() {
  return (
    <span className="signal signal--mac">
      <svg
        className="signal__arcs"
        viewBox="0 0 64 30"
        fill="none"
        focusable="false"
      >
        {SIGNAL_ARC_PATHS.map((d, index) => (
          <path
            key={d}
            className={`signal__arc signal__arc--${index + 1}`}
            stroke="currentColor"
            strokeWidth="5"
            strokeLinecap="round"
            d={d}
          />
        ))}
      </svg>
      <span className="signal__ripple signal__ripple--1" />
      <span className="signal__ripple signal__ripple--2" />
    </span>
  );
}

/** Tiny status-bar glyphs, shared by the Mac's menu bar (spec B:
 * "signal/Wi‑Fi/battery glyphs"). Local helper components, not exported —
 * this file is the only consumer. The phone gets its own status bar from
 * its screenshot now, so it no longer needs these. */
function WifiGlyph({ className }: { className: string }) {
  return (
    <svg className={className} viewBox="0 0 20 14" focusable="false">
      <path
        d="M10 13.5a1.6 1.6 0 1 1 0-3.2 1.6 1.6 0 0 1 0 3.2Z"
        fill="currentColor"
      />
      <path
        d="M4.8 7.7c2.9-2.7 7.5-2.7 10.4 0"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
      <path
        d="M1.2 4.1c4.8-4.4 12.8-4.4 17.6 0"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
    </svg>
  );
}

function BatteryGlyph({ className }: { className: string }) {
  return (
    <svg className={className} viewBox="0 0 26 14" focusable="false">
      <rect
        x="0.75"
        y="0.75"
        width="21"
        height="12.5"
        rx="3"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.3"
        opacity="0.55"
      />
      <rect x="2.5" y="2.5" width="15.5" height="9" rx="1.6" fill="currentColor" />
      <rect x="23" y="4.5" width="2.2" height="5" rx="1" fill="currentColor" opacity="0.55" />
    </svg>
  );
}

export function HeroDevice() {
  return (
    <Reveal as="div" className="hero__device">
      <div className="device" aria-hidden="true">
        <div className="mac-parallax">
        <div className="mac">
          <div className="mac__display">
            <div className="mac__desktop">
              <div className="mac__menubar">
                <span className="mac__menubar-left">
                  <svg
                    className="mac__leaf"
                    viewBox="0 0 24 24"
                    focusable="false"
                  >
                    <path
                      d="M12 21c-4.4 0-8-3.6-8-8 0-4 3.2-7.4 7.2-7.9-.4 1-.6 2.1-.4 3.2.3 1.7 1.5 3 3.1 3.5 2.4.8 4.1 3 4.1 5.6 0 2-1.6 3.6-3.6 3.6H12z"
                      fill="currentColor"
                    />
                    <path
                      d="M12 21c0-3 .8-6 2.8-8.4"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="1"
                      strokeLinecap="round"
                    />
                  </svg>
                  <span className="mac__menubar-app">Finder</span>
                  <span className="mac__menubar-item">File</span>
                  <span className="mac__menubar-item">Edit</span>
                  <span className="mac__menubar-item">View</span>
                  <span className="mac__menubar-item">Go</span>
                  <span className="mac__menubar-item">Window</span>
                  <span className="mac__menubar-item">Help</span>
                </span>
                <span className="mac__menubar-spacer" />
                <span className="mac__menubar-right">
                  <img
                    className="mac__menubar-icon"
                    src={asset("/icon-mac-64.png")}
                    alt=""
                    width={16}
                    height={16}
                    decoding="async"
                  />
                  <span className="mac__menubar-status">
                    Connected · 11 ms
                  </span>
                  <WifiGlyph className="mac__menubar-glyph mac__menubar-glyph--wifi" />
                  <BatteryGlyph className="mac__menubar-glyph mac__menubar-glyph--battery" />
                  <span className="mac__menubar-time">9:41</span>
                </span>
              </div>

              <div className="mac__finder">
                <div className="mac__finder-bar">
                  <span className="mac__dot mac__dot--red" />
                  <span className="mac__dot mac__dot--yellow" />
                  <span className="mac__dot mac__dot--green" />
                  <span className="mac__finder-spacer" />
                  <span className="mac__finder-pill" />
                  <span className="mac__finder-pill" />
                </div>
                <div className="mac__finder-body">
                  <span className="mac__finder-sidebar">
                    <span className="mac__finder-row">
                      <span className="mac__finder-dot mac__finder-dot--blue" />
                      <span className="mac__finder-bar-fill" />
                    </span>
                    <span className="mac__finder-row">
                      <span className="mac__finder-dot mac__finder-dot--red" />
                      <span className="mac__finder-bar-fill" />
                    </span>
                    <span className="mac__finder-row">
                      <span className="mac__finder-dot mac__finder-dot--orange" />
                      <span className="mac__finder-bar-fill" />
                    </span>
                    <span className="mac__finder-row">
                      <span className="mac__finder-dot mac__finder-dot--purple" />
                      <span className="mac__finder-bar-fill" />
                    </span>
                    <span className="mac__finder-row">
                      <span className="mac__finder-dot mac__finder-dot--green" />
                      <span className="mac__finder-bar-fill" />
                    </span>
                  </span>
                  <span className="mac__finder-content">
                    <span className="mac__finder-grid">
                      {Array.from({ length: 8 }, (_, index) => (
                        <span
                          key={index}
                          className={
                            index === 1
                              ? "mac__finder-tile mac__finder-tile--flash"
                              : "mac__finder-tile"
                          }
                        >
                          {index === 1 && (
                            <span className="mac__finder-tile-accent" />
                          )}
                        </span>
                      ))}
                    </span>
                  </span>
                </div>
              </div>

              <div className="mac__dock">
                {Array.from({ length: DOCK_TILE_COUNT }, (_, index) => (
                  <span key={index} className="mac__dock-tile" />
                ))}
                <span className="mac__dock-separator" />
                <span className="mac__dock-tile mac__dock-tile--icon">
                  <img
                    className="mac__dock-tile-icon-img"
                    src={asset("/icon-ios-64.png")}
                    alt=""
                    width={64}
                    height={64}
                    decoding="async"
                  />
                </span>
              </div>

              <svg
                className="cursor"
                width="24"
                height="24"
                viewBox="0 0 24 24"
                focusable="false"
              >
                <path
                  d="M4 2 L4 19.5 L8.2 16 L11 21.8 L13.6 20.5 L10.9 15 L16.5 15 Z"
                  fill="#000"
                  stroke="#fff"
                  strokeWidth="1.3"
                  strokeLinejoin="round"
                />
              </svg>
            </div>

            <span className="mac__notch" />
          </div>

          <div className="mac__base">
            <span className="mac__hinge" />
          </div>
        </div>

        {/* Wi‑Fi signal burst (spec: "overlapping Wi‑Fi signal animations")
            — nested inside .mac-parallax, after .mac, so it (a) shares the
            MacBook's parallax transform/coordinate space (positioned
            relative to the MacBook, tracks it on scroll) and (b) paints
            above the MacBook: it's the last DOM node inside .mac-parallax,
            so it's the last thing painted over the MacBook itself. */}
        <div className="signals" aria-hidden="true">
          <SignalBurst />
        </div>
        </div>

        <div className="phone-parallax">
        <div className="phone">
          <div className="phone__bezel">
            <div className="phone__screen">
              <img
                className="phone__shot"
                src={asset("/screenshots/touchpad-light-480.png")}
                srcSet={`${asset("/screenshots/touchpad-light-480.png")} 480w, ${asset("/screenshots/touchpad-light-960.png")} 960w`}
                sizes="(min-width: 64rem) 240px, 44vw"
                width={480}
                height={1043}
                alt=""
                decoding="async"
                loading="eager"
              />
              <span className="phone__island" />
              <div className="phone__pad-area">
                <span className="finger" />
              </div>
            </div>
          </div>
        </div>
        </div>
      </div>

      <p className="visually-hidden">
        Illustration: an iPhone showing the Air Control touchpad screen,
        controlling a MacBook over Wi‑Fi, with the cursor following the
        touchpad.
      </p>
    </Reveal>
  );
}
