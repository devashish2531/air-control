/**
 * Every externally visible string and URL the landing page uses.
 *
 * The public product name is **Air Control** (docs/00-decisions.md, Addendum F1).
 * The apps and the source tree still say "Air Mouse" internally; nothing on this
 * site should.
 */

const GITHUB_REPO = "https://github.com/devashish2531/air-control";

export const site = {
  name: "Air Control",
  tagline:
    "Turn your iPhone into a trackpad, air mouse, keyboard and remote for your Mac",
  description:
    "Air Control turns your iPhone or iPad into a trackpad, air mouse, keyboard and presenter remote for your Mac. Free, open source, and it never leaves your local Wi-Fi network.",
  subline: "Free and open source · Local Wi‑Fi only · No accounts",

  /**
   * Scheme + host only. The path under it comes from `NEXT_PUBLIC_BASE_PATH`,
   * so `origin` is the single thing to change when a custom domain is added
   * (see docs/07-landing-page.md).
   */
  origin: "https://devashish2531.github.io",

  minimumOS: {
    ios: "iOS 18 / iPadOS 18",
    macos: "macOS 15 Sequoia",
  },

  links: {
    github: GITHUB_REPO,
    releases: `${GITHUB_REPO}/releases`,
    latestRelease: `${GITHUB_REPO}/releases/latest`,
    license: `${GITHUB_REPO}/blob/main/LICENSE`,
    security: `${GITHUB_REPO}/blob/main/SECURITY.md`,
    contributing: `${GITHUB_REPO}/blob/main/CONTRIBUTING.md`,
    protocol: `${GITHUB_REPO}/blob/main/docs/protocol.md`,
    issues: `${GITHUB_REPO}/issues`,

    /**
     * iOS waitlist. There is no backend anywhere in this project, so this is a
     * plain link. Swap it for a GitHub Discussions thread once Discussions are
     * enabled on the repo, e.g.
     *   `${GITHUB_REPO}/discussions/categories/ios-waitlist`
     */
    iosWaitlist: `${GITHUB_REPO}/issues/new?title=iOS+waitlist&body=Please+let+me+know+when+the+Air+Control+iPhone+app+is+available+for+testing.`,
  },

  /** Homebrew cask. The tap does not exist yet — see docs/07-landing-page.md. */
  homebrew: {
    available: false,
    command: "brew install --cask devashish2531/tap/air-control",
  },
} as const;
