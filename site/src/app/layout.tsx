import type { Metadata, Viewport } from "next";

import { absolute, canonicalUrl } from "@/lib/urls";
import { site } from "@/site.config";

import "./globals.css";

const ogImage = absolute("/og.png");

export const metadata: Metadata = {
  metadataBase: new URL(canonicalUrl),
  title: {
    default: `${site.name} — ${site.tagline}`,
    template: `%s — ${site.name}`,
  },
  description: site.description,
  applicationName: site.name,
  keywords: [
    "Air Control",
    "iPhone trackpad for Mac",
    "air mouse",
    "remote mouse",
    "presenter remote",
    "macOS",
    "open source",
  ],
  alternates: { canonical: canonicalUrl },
  openGraph: {
    type: "website",
    siteName: site.name,
    title: `${site.name} — ${site.tagline}`,
    description: site.description,
    url: canonicalUrl,
    locale: "en_US",
    images: [
      {
        url: ogImage,
        width: 1200,
        height: 630,
        alt: `${site.name} — ${site.tagline}`,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: `${site.name} — ${site.tagline}`,
    description: site.description,
    images: [ogImage],
  },
  robots: { index: true, follow: true },
  // No analytics, no verification tokens, nothing third-party.
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  // The page is designed for both; `prefers-color-scheme` does the rest.
  colorScheme: "light dark",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f6f7fb" },
    { media: "(prefers-color-scheme: dark)", color: "#0a1030" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
