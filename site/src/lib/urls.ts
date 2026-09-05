import { site } from "@/site.config";

/**
 * `basePath` has to be inlined at build time, so it is read from the
 * `NEXT_PUBLIC_` variable rather than from `next.config.ts` (which is not
 * importable from client code). Keep the two in step.
 */
export const basePath = (process.env.NEXT_PUBLIC_BASE_PATH ?? "").replace(
  /\/+$/,
  "",
);

/** Path to a file in `public/`, prefixed for whatever `basePath` the build uses. */
export function asset(path: `/${string}`): string {
  return `${basePath}${path}`;
}

/** Fully qualified URL, for `<meta>` tags and structured data. */
export function absolute(path: `/${string}`): string {
  return `${site.origin}${asset(path)}`;
}

/** The site's canonical URL, with the trailing slash `trailingSlash: true` produces. */
export const canonicalUrl = `${site.origin}${basePath}/`;
