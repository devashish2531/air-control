import type { MetadataRoute } from "next";

import { canonicalUrl } from "@/lib/urls";

/** Static export writes this to `out/sitemap.xml`. */
export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: canonicalUrl,
      changeFrequency: "monthly",
      priority: 1,
    },
  ];
}
