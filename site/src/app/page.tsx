import { Hero } from "@/components/Hero";
import {
  Faq,
  Features,
  HowItWorks,
  OpenSource,
  Security,
} from "@/components/Sections";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import { faqs } from "@/content";
import { canonicalUrl } from "@/lib/urls";
import { site } from "@/site.config";

/**
 * Structured data for the FAQ and the software itself. Inlined as JSON-LD so the
 * page still ships zero executable JavaScript of its own.
 */
const structuredData = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "SoftwareApplication",
      name: site.name,
      description: site.description,
      applicationCategory: "UtilitiesApplication",
      operatingSystem: `${site.minimumOS.macos}, ${site.minimumOS.ios}`,
      url: canonicalUrl,
      license: site.links.license,
      isAccessibleForFree: true,
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    },
    {
      "@type": "FAQPage",
      mainEntity: faqs.map((faq) => ({
        "@type": "Question",
        name: faq.q,
        acceptedAnswer: { "@type": "Answer", text: faq.plain },
      })),
    },
  ],
};

export default function Home() {
  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>

      <SiteHeader />

      <main id="main">
        <Hero />
        <Features />
        <HowItWorks />
        <Security />
        <OpenSource />
        <Faq />
      </main>

      <SiteFooter />

      <script
        type="application/ld+json"
        // Static, author-controlled JSON. No user input reaches this.
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
      />
    </>
  );
}
