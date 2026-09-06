import { useId } from "react";

type LogoProps = {
  /** Rendered width/height in px (square). Defaults to 28. */
  size?: number;
  className?: string;
  /** When given, the mark is announced as an image with this name;
   *  otherwise it is treated as decorative (`aria-hidden`). */
  title?: string;
};

/**
 * Air Control mark: a mouse with three concentric Wi-Fi-style signal arcs
 * above it (the app icon minus the MacBook and background tile). Filled
 * with `currentColor` so it inherits the surrounding accent/text color on
 * both light and dark surfaces.
 *
 * Geometry lives on a 64x64 grid, tuned so the mark stays legible down to
 * 24px (see the proof sheet used while designing this).
 */
export function Logo({ size = 28, className, title }: LogoProps) {
  const titleId = useId();

  return (
    <svg
      className={className}
      width={size}
      height={size}
      viewBox="0 0 64 64"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      role={title ? "img" : undefined}
      aria-hidden={title ? undefined : "true"}
      aria-labelledby={title ? titleId : undefined}
    >
      {title ? <title id={titleId}>{title}</title> : null}

      {/* Mouse body: a stadium/capsule shape (corner radius == half width)
          with a small pill-shaped scroll-slot cut out near the top via
          evenodd, so it reads correctly on any surface color. */}
      <path
        fill="currentColor"
        fillRule="evenodd"
        d="M32 24a13 13 0 0 1 13 13v10a13 13 0 0 1-13 13 13 13 0 0 1-13-13V37a13 13 0 0 1 13-13Zm0 6a1.5 1.5 0 0 1 1.5 1.5v6a1.5 1.5 0 0 1-3 0v-6A1.5 1.5 0 0 1 32 30Z"
      />

      {/* Three concentric signal arcs, centred on the mouse's top, each
          spanning ~100 degrees. */}
      <path
        stroke="currentColor"
        strokeWidth="5"
        strokeLinecap="round"
        d="M25.11 20.22A9 9 0 0 1 32 17a9 9 0 0 1 6.89 3.22"
      />
      <path
        stroke="currentColor"
        strokeWidth="5"
        strokeLinecap="round"
        d="M19.74 15.72A16 16 0 0 1 32 10a16 16 0 0 1 12.26 5.72"
      />
      <path
        stroke="currentColor"
        strokeWidth="5"
        strokeLinecap="round"
        d="M14.38 11.22A23 23 0 0 1 32 3a23 23 0 0 1 17.62 8.22"
      />
    </svg>
  );
}

export default Logo;
