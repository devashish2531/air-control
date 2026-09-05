import type { MetadataRoute } from "next";

import { absolute } from "@/lib/urls";

/** Static export writes this to `out/robots.txt`. */
export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [{ userAgent: "*", allow: "/" }],
    sitemap: absolute("/sitemap.xml"),
  };
}
