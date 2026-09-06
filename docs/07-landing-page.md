# Air Control — Landing Page

| Field | Value |
|---|---|
| Document | 07-landing-page.md |
| Status | Built and verified locally; awaiting first Pages deploy |
| Date | 2026-09-05 |
| Upstream | `docs/00-decisions.md` Addendum F, `docs/01-requirements.md` §1–2 |
| Scope | `site/**`, `.github/workflows/site.yml` |
| Live URL | https://devashish.cc/air-control/ |

---

## 1. What this is

A single-page public marketing site for the project, built as a **fully static
export** and published to **GitHub Pages**. It has no backend, no database, no
forms that post anywhere, no analytics and no third-party requests at runtime.

The site is also the host for the **Sparkle appcast** (`/appcast.xml`) that the
Mac helper's updater will poll (`00-decisions.md` A6, D5, F2).

### 1.1 The name

The public product name is **Air Control**, matching the GitHub repository
`devashish2531/air-control` (`00-decisions.md` Addendum F1, which supersedes the
open item in A8). The apps, bundle identifiers (`com.aircontrol.*`), the Swift
package (`AirControlKit`) and every other document now use this name consistently.
A guard in the site workflow (`grep -q "Air Control" out/index.html`) checks that
the built page actually renders it; the strong version of that check is code review.

### 1.2 Content sources

| Section | Drawn from |
|---|---|
| Hero promise, positioning | `01-requirements.md` §1 (vision), §2 (personas) |
| Six feature cards | `01-requirements.md` §3, epics TP / GY / KB / PR / MC / IP |
| How it works (3 steps) | Epic DP (AM-DP-02), Epic OB, Epic MB |
| Latency claim | `01-requirements.md` §1.2 M2 and `00-decisions.md` "Performance" — stated on the page as a **design target**, not a guarantee |
| Security section | `00-decisions.md` A1, A2, A5, A9; `SECURITY.md` |
| Minimum OS in the FAQ | `00-decisions.md` "Distribution & stack" — iOS 18 / macOS 15 |

---

## 2. Stack and why

| Choice | Version | Rationale |
|---|---|---|
| Next.js, App Router, TypeScript | 16.3.4 | Owner's decision (Addendum F2). `output: 'export'` reduces it to a static file emitter, so no server feature is reachable by accident. |
| React | 19.2.8 | Required by Next 16. |
| TypeScript | 5.9.3 | 5.x line rather than the 7.0 native port, which the Next toolchain has not settled on. |
| ESLint + `eslint-config-next` | 9.39.5 / 16.3.4 | Flat config; `eslint-config-next` 16 exports flat arrays directly, so no `FlatCompat` shim. |
| Styling | — | One hand-written stylesheet (`src/app/globals.css`), CSS custom properties, no framework. Tailwind was permitted but buys nothing for one page and adds a build step. |
| Fonts | — | System stack (`-apple-system`, …). No webfont, so no `fonts.googleapis.com`, no FOUT, no third-party request. |

Every dependency version in `site/package.json` is **pinned exactly** (no `^`,
no `~`). CI installs with `npm ci` against the committed `package-lock.json`.
npm only — no pnpm, no yarn.

### 2.1 No JavaScript is required to read the page

Every component is a server component; there is no `"use client"` anywhere. The
FAQ uses native `<details>`/`<summary>`, the nav uses in-page anchors with
`scroll-behavior: smooth`, and theming is `prefers-color-scheme` only. Next still
ships its runtime chunks, but the page is fully readable and navigable with
JavaScript disabled.

---

## 3. Node on a machine without Homebrew

This project's dev machine has no Homebrew (`00-decisions.md` D2). Check first:

```sh
node -v      # want v22.x
npm -v
```

**As verified on 2026-09-05 the machine already had Node v22.20.0 and npm 10.9.3
installed, so no download was needed.** If a machine does not:

```sh
cd "<repo root>"
mkdir -p tools/node && cd tools/node
# Pick the current v22 LTS build from https://nodejs.org/dist/latest-v22.x/
curl -fsSLO "https://nodejs.org/dist/latest-v22.x/node-v22.20.0-darwin-arm64.tar.gz"
tar -xzf node-v22.20.0-darwin-arm64.tar.gz --strip-components=1
rm node-v22.20.0-darwin-arm64.tar.gz
export PATH="$(pwd)/bin:$PATH"
node -v
```

- Use `darwin-x64` instead of `darwin-arm64` on an Intel Mac.
- `tools/node/` is git-ignored (alongside the existing `tools/bin/` used for
  XcodeGen), so nothing lands in the repository.
- `export PATH=".../tools/node/bin:$PATH"` has to be repeated in every shell that
  builds the site — it is deliberately not written into any dotfile.
- CI does not use this at all; GitHub Actions installs Node with
  `actions/setup-node`.

---

## 4. Layout

```
site/
├── package.json            exact pinned versions; scripts: dev/build/lint/typecheck/serve/assets
├── package-lock.json       committed; `npm ci` builds from it
├── next.config.ts          output: 'export', trailingSlash, images.unoptimized, basePath from env
├── tsconfig.json
├── eslint.config.mjs
├── README.md               how to run it, day to day
├── public/                 copied byte-for-byte into out/
│   ├── .nojekyll
│   ├── appcast.xml         Sparkle feed placeholder
│   ├── icon-ios.png        384px, transparent corners
│   ├── icon-mac.png        384px, transparent corners
│   └── og.png              1200x630 Open Graph card
├── scripts/
│   ├── make-assets.sh      regenerates every PNG in public/ (and the favicons)
│   └── make-assets.swift   CoreGraphics + CoreText; macOS + Xcode only
└── src/
    ├── site.config.ts      product name, every outbound URL, minimum OS, Homebrew command
    ├── content.tsx         feature cards, the three steps, security bullets, FAQ
    ├── lib/urls.ts         basePath-aware asset() / absolute() / canonicalUrl
    ├── app/
    │   ├── layout.tsx      <meta>, Open Graph, Twitter card, theme-color, viewport
    │   ├── page.tsx        section order + JSON-LD (SoftwareApplication + FAQPage)
    │   ├── globals.css     the whole stylesheet
    │   ├── icon.png        favicon (512)  — generated
    │   ├── apple-icon.png  touch icon (180) — generated
    │   ├── robots.ts       -> out/robots.txt
    │   └── sitemap.ts      -> out/sitemap.xml
    └── components/
        ├── SiteHeader.tsx  brand + Features / How it works / Security / FAQ / GitHub
        ├── Hero.tsx
        ├── Sections.tsx    Features, HowItWorks, Security, OpenSource, Faq
        └── SiteFooter.tsx  GitHub, license, privacy, Apple disclaimer
```

### 4.1 Where the content lives

Nothing user-visible is hard-coded inside a component:

- `src/site.config.ts` — the product name, the tagline, the sub-line, the
  minimum OS strings, and every outbound URL (releases, license, SECURITY.md,
  CONTRIBUTING.md, protocol.md, issues, **and the iOS waitlist**).
- `src/content.tsx` — the six feature cards, the three steps, the six security
  bullets and the six FAQ entries. Each FAQ entry carries a rendered `a` (JSX)
  and a `plain` string; the `plain` one feeds the JSON-LD `FAQPage` block, so
  the two must be kept in step.

### 4.2 Download calls to action

| Button | Target | Constant |
|---|---|---|
| Download for Mac | `https://github.com/devashish2531/air-control/releases/latest` | `site.links.latestRelease` |
| Get for iPhone | Waitlist link + a "Coming soon" badge | `site.links.iosWaitlist` |

The iOS waitlist is a **single config constant**, currently a pre-filled
`issues/new` URL (no backend exists anywhere in this project, by design). Point
it at a GitHub Discussions category once Discussions are enabled on the repo:

```ts
iosWaitlist: `${GITHUB_REPO}/discussions/categories/ios-waitlist`,
```

A `mailto:` also works. Replace the URL, nothing else.

The hero also shows a Homebrew snippet, gated on `site.homebrew.available`
(currently `false`, so the page says the cask is not published yet). When the tap
exists, flip the flag and correct the command.

### 4.3 Images

`site/scripts/make-assets.sh` compiles and runs `make-assets.swift`, which:

1. Reads `design/icons/ios-icon-source.png` (bright) and `mac-icon-source.png`
   (dark). Both are 1254×1254 with the artwork drawn as a rounded square on a
   white ground.
2. Finds the artwork's bounding box by scanning for pixels that are neither
   near-white nor transparent, and measures the source's **own** corner radius
   from the span of its top row (a rounded rect's top edge runs from `minX + r`
   to `maxX - r`).
3. Crops to that box and re-renders it at 384 px clipped to that same radius, so
   the corners come out transparent and the icon sits correctly on both the light
   and the dark page background. The 512 px favicon and 180 px touch icon come
   from the same path.
4. Draws the 1200×630 Open Graph card: navy ground, diagonal gradient, the macOS
   icon at 260 px, and three lines of system-font text via CoreText.

It requires macOS and Xcode (`DEVELOPER_DIR` defaults to `/Applications/Xcode.app/…`).
**CI never runs it** — the PNGs are committed — so the Linux runner needs nothing.

Run it after any change to the source artwork:

```sh
cd site && npm run assets
```

---

## 5. `basePath`, and how the same build serves two URLs

`next.config.ts` reads `NEXT_PUBLIC_BASE_PATH`:

| Deployment | `NEXT_PUBLIC_BASE_PATH` | Result |
|---|---|---|
| GitHub Pages project site | `/air-control` | assets at `/air-control/_next/…`, canonical `https://devashish.cc/air-control/` |
| Custom domain, and `npm run dev` | unset / empty | assets at `/_next/…` |

`basePath` and `assetPrefix` are both set from it. `trailingSlash: true` makes
Next emit `out/foo/index.html`, which is what GitHub Pages needs to serve `/foo/`
without a rewrite rule.

**One trap worth writing down:** `next/image` with `images.unoptimized: true`
emits the `src` **without** the basePath, so hero images 404 on the project site.
The page therefore uses plain `<img>` with `asset()` from `src/lib/urls.ts`,
which applies the prefix, and turns off `@next/next/no-img-element` in
`eslint.config.mjs` with that reason in a comment. Every `<img>` still carries
explicit `width`/`height`, so cumulative layout shift stays at zero — which is
the only thing `next/image` would have bought here anyway.

Anything referencing a file in `public/` must go through `asset()` (relative) or
`absolute()` (for `<meta>` tags). `src/site.config.ts` holds `origin`
(scheme + host only); `canonicalUrl` is `origin + basePath + "/"`.

---

## 6. The Sparkle appcast at `/appcast.xml`

`site/public/appcast.xml` is a **placeholder**: a valid RSS 2.0 document with the
Sparkle namespace and zero `<item>` elements, which Sparkle reads as "you are up
to date". A commented-out `<item>` template inside the file shows the shape a
real entry takes, including the mandatory `sparkle:edSignature`.

Two properties make this work, and both are verified in CI:

1. **Static export copies `public/` verbatim.** Next does not parse, rewrite or
   route anything under `public/`, so `out/appcast.xml` is byte-identical to
   `site/public/appcast.xml`. Verified locally with `curl` (`200`,
   `application/xml`, 1876 bytes).
2. **Unknown paths do not swallow it.** There is no catch-all route, no rewrite
   and no middleware — a static export cannot have any. `out/404.html` only ever
   serves paths with no file behind them, and `appcast.xml` has one. The site
   workflow fails the build if `out/appcast.xml` is missing.

Once Sparkle lands (M8) the release workflow should write real entries into this
file (or generate it), signed with `sign_update`. The final feed URL is
`https://devashish.cc/air-control/appcast.xml`, which is what
`SUFeedURL` in the Mac app's `Info.plist` must point at — note that it includes
the `/air-control` basePath, so **moving to a custom domain changes the feed URL
and requires an app update** to match. If a custom domain is likely, set it up
before shipping the first Sparkle-enabled build.

---

## 7. Deployment

### 7.1 The workflow

`.github/workflows/site.yml`:

- **Triggers:** push to `main` touching `site/**` or the workflow file itself,
  plus `workflow_dispatch` for a manual run from the Actions tab.
- **Permissions:** `contents: read`, `pages: write`, `id-token: write` (the OIDC
  token `actions/deploy-pages` needs).
- **Concurrency:** group `pages`, `cancel-in-progress: false` — never kill a
  deploy that is already publishing.
- **Build job:** `actions/checkout@v4` → `actions/setup-node@v4` (Node 22, npm
  cache keyed on `site/package-lock.json`) → `npm ci` → `npm run lint` →
  `npm run typecheck` → `npm run build` with `NEXT_PUBLIC_BASE_PATH=/air-control`
  → a verification step that asserts `out/index.html`, `out/appcast.xml` and
  `out/.nojekyll` all exist and that the HTML says "Air Control" →
  `actions/upload-pages-artifact@v3` with `path: site/out`.
- **Deploy job:** `actions/deploy-pages@v4` in the `github-pages` environment.

`defaults.run.working-directory: site` keeps every `run` step in `site/`; action
`path` inputs are relative to the workspace root, hence `site/out`.

### 7.2 One-time setup the owner must do

The workflow cannot enable Pages for the repository. Once, by hand:

1. Push this branch to `main` on `github.com/devashish2531/air-control`.
2. **Settings → Pages → Build and deployment → Source: `GitHub Actions`.**
   (Not "Deploy from a branch". No `gh-pages` branch is involved.)
3. Actions → **Site** → *Run workflow* to publish immediately, or just push a
   change under `site/`.
4. The URL appears on the workflow run and under Settings → Pages:
   `https://devashish.cc/air-control/`.

If step 2 is skipped, the deploy job fails with a "Pages is not enabled" error;
the build job still passes.

### 7.3 Custom domain

The owner's GitHub Pages user site already carries the custom domain `devashish.cc`,
so this project site is served at `https://devashish.cc/air-control/` automatically
(the `www` host is the canonical origin in `site/src/site.config.ts`; the apex
redirects to it). No `CNAME` file is needed in `site/public/` and `NEXT_PUBLIC_BASE_PATH`
stays `/air-control`. If the site ever moves to its own hostname, add
`site/public/CNAME` with that hostname, set `NEXT_PUBLIC_BASE_PATH` to empty in
`site.yml`, and update `ORIGIN` in `site.config.ts`.

## 8. Local workflow

```sh
cd site
npm install                                  # first time (npm ci in CI)

npm run dev                                  # http://localhost:3000, no basePath
npm run build                                # -> site/out/
npm run serve                                # npx serve -l 4173 out
npm run lint
npm run typecheck
npm run assets                               # regenerate PNGs (macOS + Xcode)

NEXT_PUBLIC_BASE_PATH=/air-control npm run build   # exactly what CI publishes
```

A `basePath` build **cannot** be previewed by serving `out/` at the root; its
asset URLs begin with `/air-control/`. Build without the variable to preview.

`site/out/`, `site/.next/`, `site/node_modules/`, `site/next-env.d.ts` and
`tools/node/` are all in the repository's `.gitignore`.

---

## 9. Design and accessibility notes

- **Responsive.** One `.container` (max 1120 px) with a fluid gutter. The hero
  is a single column below 60rem and two above; the card grids use
  `repeat(auto-fit, minmax(min(100%, 17rem), 1fr))`, so they reflow with no
  breakpoint list. The four in-page nav links collapse below 40rem, leaving the
  brand and the GitHub link.
- **Dark and light.** The full light palette is defined on bare `:root`; a
  single `@media (prefers-color-scheme: dark)` block redefines the same tokens.
  `<meta name="theme-color">` is supplied per scheme, and `color-scheme: light dark`
  makes form controls and scrollbars follow.
- **Keyboard.** A "Skip to content" link is the first focusable element. A single
  `:focus-visible` rule paints a 3 px accent outline with a 3 px offset on
  everything. `scroll-padding-top` keeps anchored headings clear of the sticky
  header.
- **Semantics.** `header` / `nav[aria-label]` / `main` / `section[aria-labelledby]`
  / `article` / `footer`; one `h1`, `h2` per section, `h3` per card; the steps are
  an `<ol>` numbered by CSS counters (so the numbers are decoration, not content);
  the facts list is a `<dl>` with `<div>` wrappers.
- **Contrast.** Every text/background pair was measured. Light: body `#4d5570`
  on `#f6f7fb` is 6.9:1, the muted `#5f6784` is 5.2:1 (4.9:1 on the sunken
  section band), links 7.3:1, headings 17:1. Dark: body 9.9:1, muted 7.0:1,
  links 9.8:1, headings 16.5:1. The primary button is 6.7:1 in light and 7.4:1
  in dark. The lowest value anywhere is 4.9:1, comfortably past AA for normal
  text.
- **Motion.** A `prefers-reduced-motion: reduce` block disables smooth scrolling
  and collapses every transition.
- **Lighthouse.** No render-blocking third party, no webfont, every image has
  explicit `width`/`height`, the hero images are `fetchPriority="high"`, and the
  two hero PNGs are 384 px (≈ 185 KB each) rather than the 512 px masters.
  The Open Graph card is only fetched by crawlers.
- **Privacy.** No cookies, no `localStorage`, no analytics, no external requests
  at runtime. The footer states this, plus that the apps collect no data, plus
  the "not affiliated with Apple" disclaimer.
- **SEO.** Canonical link, description, Open Graph and Twitter `summary_large_image`
  tags, `robots.txt` and `sitemap.xml` generated from the same `origin` constant,
  and inline JSON-LD (`SoftwareApplication` + `FAQPage`).

---

## 10. Verification performed (2026-09-05)

| Check | Result |
|---|---|
| `npm run build` (no basePath) | Pass — 7 static routes |
| `NEXT_PUBLIC_BASE_PATH=/air-control npm run build` | Pass; `out/index.html` present; every asset URL prefixed `/air-control/` |
| `npx tsc --noEmit` | Clean |
| `npm run lint` | Clean, 0 warnings |
| `npx serve -l 4173 out`, `curl /` | `200 text/html`, 52 KB |
| `curl /appcast.xml` | `200 application/xml`, 1876 bytes, byte-identical to the source |
| `curl /robots.txt`, `/sitemap.xml`, `/icon-ios.png`, `/og.png`, `/icon.png` | all `200` |
| `curl /nonexistent-path` | `404` (does not shadow `/appcast.xml`) |
| Section anchors present in `out/index.html` | `#features`, `#how-it-works`, `#security`, `#open-source`, `#faq`, `#top` |
| Occurrences of the internal codename in `out/index.html` | **0** |
| Headless-Chrome screenshots, light and dark | Both render correctly at 1280 px |
| `ruby -ryaml` on `.github/workflows/site.yml` | Parses; two jobs, correct `permissions` and `on:` |

### Not done

- **Lighthouse was not run.** No CI-grade Chrome driver is set up in this repo and
  installing one was out of scope. The page was built against Lighthouse's
  structural criteria (semantic HTML, sized images, contrast, focus states,
  no blocking third parties) but the score is unmeasured.
- **The GitHub Pages deploy has not run**, because Pages is not enabled on the
  repository yet (§7.2). The workflow YAML is validated but untested end to end.
- **`design/icons/README.md` still has a TODO about the artwork's licence and
  attribution.** The site publishes those images. That TODO should be resolved
  before the site goes public.
- **No screenshots of the apps.** The hero shows the two app icons; real product
  screenshots should replace or join them once the apps are demoable.
