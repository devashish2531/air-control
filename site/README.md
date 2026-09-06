# Air Control — landing page

The public marketing site for the project, at
<https://devashish2531.github.io/air-control/>.

**The public product name is "Air Control".** The apps, bundle identifiers and the
rest of `docs/` still say "Air Mouse" internally and will be renamed in a later
pass (`docs/00-decisions.md`, Addendum F1). Nothing rendered by this site should
say "Air Mouse".

| | |
| --- | --- |
| Framework | Next.js 16 (App Router, TypeScript), `output: 'export'` — no server runtime |
| Styling | Three hand-written stylesheets — `globals.css` (tokens, reset, typography, shared primitives, header/footer chrome), `hero.css` (Hero/HeroDevice), `sections.css` (Features/HowItWorks/Security/OpenSource/Faq/FinalCta) — joined by `@import` at the top of `globals.css`. No Tailwind, no CSS-in-JS |
| Fonts / CDNs | None. System font stack, no external requests of any kind |
| Analytics | None |
| JavaScript | Two small client components (`SiteHeader` for scroll/menu state, `Reveal` for scroll-triggered reveals) — no other JS of the page's own. `prefers-reduced-motion`, `prefers-reduced-transparency` and `prefers-contrast` are all honored |
| Dependencies | `qrcode` is used only at build time inside a server component (`HeroQR`) to inline the hero QR SVG; no JS ships to the browser for it |
| Hosting | GitHub Pages, via `.github/workflows/site.yml` |

Full background, deploy steps and the custom-domain switch:
[`docs/07-landing-page.md`](../docs/07-landing-page.md).

## Requirements

Node **22 LTS** and npm (npm only — no pnpm, no yarn). Dependency versions are
pinned exactly in `package.json`; always install with `npm ci` in CI.

If the machine has no Node, install it without Homebrew:

```sh
mkdir -p tools/node && cd tools/node
curl -fsSLO "https://nodejs.org/dist/latest-v22.x/node-v22.20.0-darwin-arm64.tar.gz"
tar -xzf node-v22.20.0-darwin-arm64.tar.gz --strip-components=1
export PATH="$PWD/bin:$PATH"      # add to every shell that builds the site
```

`tools/node/` is git-ignored. Substitute `darwin-x64` on an Intel Mac and take
whatever `v22.*` the [directory listing](https://nodejs.org/dist/latest-v22.x/)
currently holds.

## Local development

```sh
cd site
npm install
npm run dev            # http://localhost:3000
```

`npm run dev` runs with no `basePath`, which is the same shape a custom domain
would have.

## Building and previewing the static export

```sh
npm run build          # -> site/out/
npm run serve          # npx serve -l 4173 out  ->  http://localhost:4173
```

To reproduce exactly what CI publishes (mounted under `/air-control/`):

```sh
NEXT_PUBLIC_BASE_PATH=/air-control npm run build
```

Note that a `basePath` build cannot be previewed by serving `out/` at the root —
its asset URLs start with `/air-control/`. Build without the variable for local
preview.

## Checks

```sh
npm run lint           # eslint (flat config, eslint-config-next)
npm run typecheck      # tsc --noEmit
```

## Layout

```
site/
├── next.config.ts          output: 'export', trailingSlash, basePath from env
├── eslint.config.mjs
├── public/                 copied verbatim into out/
│   ├── .nojekyll           tells GitHub Pages not to run Jekyll
│   ├── appcast.xml         Sparkle feed placeholder, served at /appcast.xml
│   ├── icon-ios.png        384px master, transparent corners
│   ├── icon-ios-64.png     64px, sips-downsized — what actually renders (16-28px)
│   ├── icon-mac.png        384px master, transparent corners
│   ├── icon-mac-64.png     64px, sips-downsized — what actually renders (16-28px)
│   └── og.png              1200x630 Open Graph card
├── scripts/
│   ├── make-assets.sh      regenerates every PNG above from design/icons/, then sips's the -64 variants and the favicon down
│   └── make-assets.swift   CoreGraphics/CoreText; macOS + Xcode only
└── src/
    ├── site.config.ts      every user-visible URL and name, in one place
    ├── content.tsx         features, steps, security points, FAQ
    ├── lib/urls.ts         basePath-aware asset() / absolute()
    ├── app/                layout.tsx, page.tsx, globals.css + hero.css + sections.css, robots.ts, sitemap.ts
    └── components/         SiteHeader, Hero, HeroDevice, Sections, SiteFooter, Reveal
```

## Editing content

Almost everything is data:

- **Links, product name, waitlist target, Homebrew command** — `src/site.config.ts`.
  The iOS waitlist is a single constant (`links.iosWaitlist`); point it at a
  GitHub Discussions category once Discussions are enabled.
- **Feature cards, the three steps, security bullets, FAQ** — `src/content.tsx`.
  Each FAQ entry carries both rich `a` (rendered) and `plain` (used for the
  JSON-LD `FAQPage` block) — keep the two in step.

## Regenerating images

```sh
npm run assets     # or: ./scripts/make-assets.sh
```

Reads `design/icons/{ios,mac}-icon-source.png`, finds the artwork inside its
white margin, measures the source's own corner radius, and re-renders each icon
with transparent corners plus the Open Graph card. Requires macOS and Xcode;
CI never runs it, because the PNGs are committed.

## Regenerating gallery screenshots

```sh
./scripts/make-screenshots.sh
```

Reads the 1206×2622 device masters from `design/screenshots/` (not shipped —
outside `public/`) and, with macOS `sips`, writes `<slug>-<mode>-480.png` and
`<slug>-<mode>-960.png` into `public/screenshots/` for each of the six screens
(`touchpad`, `air-mouse`, `keyboard`, `remote`, `macros`, `settings`) in both
`light` and `dark` mode — 24 files, used by the gallery section's `srcset`.

## Deploying

Pushing to `main` with anything under `site/**` changed runs
`.github/workflows/site.yml`, which builds with `NEXT_PUBLIC_BASE_PATH=/air-control`
and publishes `site/out` to GitHub Pages. It can also be run by hand from the
Actions tab (`workflow_dispatch`).

One-time setup: in the repository settings under Pages, set the source to
**GitHub Actions**. Do not click "Configure" on GitHub's suggested Next.js
workflow: it expects the app at the repository root and fails with "Unable to
determine package manager". `site.yml` already handles the `site/` folder.
