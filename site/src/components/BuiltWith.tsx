import type { CSSProperties } from "react";

/**
 * Same helper as Hero.tsx's `inDelay` / HeroQR.tsx's local copy — drives the
 * `.hero__in` + `--in-delay` entrance hook defined in hero.css. Copied
 * locally rather than imported, for the same reason HeroQR.tsx gives (avoid
 * a cross-component dependency for a two-line helper).
 */
function inDelay(ms: number): CSSProperties {
  return { "--in-delay": `${ms}ms` } as CSSProperties;
}

const CHIPS: ReadonlyArray<{ readonly label: string; readonly glyph?: boolean }> = [
  { label: "Swift 6", glyph: true },
  { label: "SwiftUI", glyph: true },
  { label: "CryptoKit" },
];

/**
 * Official Swift language mark — Apple's own Swift logo (swift.org), used
 * here on the "Swift 6" and "SwiftUI" chips under Apple's Swift trademark
 * guidelines (https://www.swift.org/legal/), which permit using the logo to
 * refer to the Swift language itself; this does not imply Apple endorsement
 * of Air Control. Paths inlined verbatim from swift.org's own SVG (viewBox
 * 0 0 59.391 59.391): an orange (#F05138, Swift's brand colour) rounded-
 * square tile with the white bird mark. CryptoKit has no equivalent mark.
 */
function SwiftMark() {
  return (
    <svg
      className="chip__glyph"
      width="16"
      height="16"
      viewBox="0 0 59.391 59.391"
      aria-hidden="true"
      focusable="false"
    >
      <path
        fill="#F05138"
        d="M59.387 16.45a82.463 82.463 0 0 0-.027-1.792c-.035-1.301-.112-2.614-.343-3.9-.234-1.307-.618-2.523-1.222-3.71a12.464 12.464 0 0 0-5.453-5.452C51.156.992 49.941.609 48.635.374c-1.288-.232-2.6-.308-3.902-.343a85.714 85.714 0 0 0-1.792-.027C42.23 0 41.52 0 40.813 0H18.578c-.71 0-1.419 0-2.128.004-.597.004-1.195.01-1.792.027-.325.009-.651.02-.978.036-.978.047-1.959.133-2.924.307-.98.176-1.908.436-2.811.81A12.503 12.503 0 0 0 3.89 3.89a12.46 12.46 0 0 0-2.294 3.158C.992 8.235.61 9.45.374 10.758c-.231 1.286-.308 2.599-.343 3.9a85.767 85.767 0 0 0-.027 1.792C-.001 17.16 0 17.869 0 18.578v22.235c0 .71 0 1.418.004 2.128.004.597.01 1.194.027 1.791.035 1.302.112 2.615.343 3.901.235 1.307.618 2.523 1.222 3.71a12.457 12.457 0 0 0 5.453 5.453c1.186.603 2.401.986 3.707 1.22 1.287.232 2.6.31 3.902.344.597.016 1.195.023 1.793.027.709.005 1.417.004 2.127.004h22.235c.709 0 1.418 0 2.128-.004.597-.004 1.194-.011 1.792-.027 1.302-.035 2.614-.112 3.902-.343 1.306-.235 2.521-.618 3.707-1.222a12.461 12.461 0 0 0 5.453-5.452c.604-1.187.987-2.403 1.222-3.71.231-1.286.308-2.6.343-3.9.016-.598.023-1.194.027-1.792.004-.71.004-1.419.004-2.129V18.578c0-.71 0-1.419-.004-2.128z"
      />
      <path
        fill="#FFF"
        d="m47.06 36.66-.004-.004c.066-.224.134-.446.191-.675 2.465-9.821-3.55-21.432-13.731-27.546 4.461 6.048 6.434 13.374 4.681 19.78-.156.571-.344 1.12-.552 1.653-.225-.148-.51-.316-.89-.527 0 0-10.127-6.252-21.103-17.312-.288-.29 5.852 8.777 12.822 16.14-3.284-1.843-12.434-8.5-18.227-13.802.712 1.187 1.558 2.33 2.489 3.43C17.573 23.932 23.882 31.5 31.44 37.314c-5.31 3.25-12.814 3.502-20.285.003a30.646 30.646 0 0 1-5.193-3.098c3.162 5.058 8.033 9.423 13.96 11.97 7.07 3.039 14.1 2.833 19.336.05l-.004.007c.024-.016.055-.032.08-.047.214-.116.428-.234.636-.358 2.516-1.306 7.485-2.63 10.152 2.559.654 1.27 2.041-5.46-3.061-11.74z"
      />
    </svg>
  );
}

/**
 * "Works with iPhone | iPad | Mac" — an outlined accessory-style badge in
 * the spirit of Apple's own (2px outline, rounded corners, two-line stack),
 * but deliberately NOT Apple's "Made for iPhone/iPad" (MFi) badge: no Apple
 * logo, our own typography, and "Works with" rather than "Made for". MFi is
 * a licensed program/trademark for certified accessories; Air Control is
 * not part of it and makes no such claim — this is a plain, honest
 * description of what the app talks to.
 *
 * `role="img"` + `aria-label` follows the same pattern HeroQR.tsx uses for
 * its QR code: the visible markup is a purely visual lockup, so the whole
 * thing is exposed to assistive tech as one labelled unit rather than
 * fragments ("Works with", "iPhone", "Mac", …).
 */
function WorksWithBadge() {
  return (
    <div className="workswith" role="img" aria-label="Works with iPhone, iPad and Mac">
      <span className="workswith__top">Works with</span>
      <span className="workswith__bottom">
        <span>iPhone</span>
        <span className="workswith__sep" />
        <span>iPad</span>
        <span className="workswith__sep" />
        <span>Mac</span>
      </span>
    </div>
  );
}

/**
 * Hero "Built with" strip (server component, no client JS): a row of
 * technology chips plus a "Works with" badge, sitting directly under the QR
 * card in the hero's right column. Joins the same load-in stagger as the
 * rest of the hero (`.hero__in` / `--in-delay`) at 450ms — after the QR
 * card's 360ms — rather than the scroll-triggered `<Reveal>` used further
 * down the page, since it's part of the first screen.
 */
export function BuiltWith() {
  return (
    <div className="builtwith hero__in" style={inDelay(450)}>
      <p className="builtwith__label">Built with</p>

      <ul className="builtwith__chips">
        {CHIPS.map((chip) => (
          <li className="chip" key={chip.label}>
            {chip.glyph ? <SwiftMark /> : null}
            {chip.label}
          </li>
        ))}
      </ul>

      <WorksWithBadge />
    </div>
  );
}
