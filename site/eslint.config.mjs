// eslint-config-next 16 ships flat config directly — no FlatCompat needed.
import coreWebVitals from "eslint-config-next/core-web-vitals";
import typescript from "eslint-config-next/typescript";

const config = [
  { ignores: [".next/**", "out/**", "node_modules/**", "next-env.d.ts"] },
  ...coreWebVitals,
  ...typescript,
  {
    rules: {
      // `output: 'export'` + `images.unoptimized` means next/image degrades to a
      // plain <img> anyway, while adding client JS and dropping the basePath
      // from the src. Every <img> here carries explicit width/height.
      "@next/next/no-img-element": "off",
    },
  },
];

export default config;
