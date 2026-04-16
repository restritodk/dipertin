/**
 * Gera sitemap.xml com base na variável de ambiente SITE_BASE_URL
 * (ou https://www.dipertin.com.br por omissão).
 *
 * Uso: SITE_BASE_URL=https://seudominio.com.br node scripts/generate-sitemap.mjs
 */
import { writeFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const base = (process.env.SITE_BASE_URL || "https://www.dipertin.com.br").replace(/\/$/, "");
const today = new Date().toISOString().slice(0, 10);

const paths = [
  { loc: "/", priority: "1.0", changefreq: "weekly" },
  { loc: "/produto.html", priority: "0.8", changefreq: "weekly" },
  { loc: "/loja.html", priority: "0.8", changefreq: "weekly" },
];

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${paths
  .map(
    (p) => `  <url>
    <loc>${base}${p.loc}</loc>
    <lastmod>${today}</lastmod>
    <changefreq>${p.changefreq}</changefreq>
    <priority>${p.priority}</priority>
  </url>`
  )
  .join("\n")}
</urlset>
`;

const out = join(__dirname, "..", "sitemap.xml");
writeFileSync(out, xml, "utf8");
console.log("sitemap.xml gerado:", out, "| base:", base);
