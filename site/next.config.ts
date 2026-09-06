import type { NextConfig } from "next";

/**
 * `NEXT_PUBLIC_BASE_PATH` decides where the site is mounted.
 *
 *   - GitHub Pages project site (https://devashish2531.github.io/air-control/)
 *       NEXT_PUBLIC_BASE_PATH=/air-control
 *   - custom domain, or `npm run dev`
 *       unset (or empty)
 *
 * The value is read at build time by the workflow in `.github/workflows/site.yml`
 * and by `src/lib/asset.ts` for anything referenced from `public/`.
 */
const rawBasePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";
const basePath = rawBasePath.replace(/\/+$/, "");

const nextConfig: NextConfig = {
  // Fully static: `next build` emits `out/` with no server runtime at all.
  output: "export",
  // No trailing slashes: production is https://www.devashish.cc/air-control,
  // served through the portfolio's Vercel rewrite, and that host normalises
  // trailing slashes away. Metadata URLs (canonical, Open Graph, sitemap) must
  // match that form. The single page still exports as `out/index.html`.
  trailingSlash: false,
  // The static export has no image optimizer.
  images: { unoptimized: true },
  basePath: basePath || undefined,
  assetPrefix: basePath || undefined,
  reactStrictMode: true,
  // No `X-Powered-By` in the generated HTML/headers.
  poweredByHeader: false,
};

export default nextConfig;
