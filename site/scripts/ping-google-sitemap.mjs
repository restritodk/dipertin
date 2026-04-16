/**
 * Pedido HTTP ao endpoint de ping do Google (pode ser ignorado em favor do
 * Search Console → Sitemaps). Execute após deploy. SITE_BASE_URL opcional.
 */
import https from "https";

const base = (process.env.SITE_BASE_URL || "https://www.dipertin.com.br").replace(/\/$/, "");
const url = `https://www.google.com/ping?sitemap=${encodeURIComponent(base + "/sitemap.xml")}`;

https
  .get(url, (res) => {
    console.log("Ping Google sitemap:", res.statusCode, url);
    res.resume();
  })
  .on("error", (e) => {
    console.error(e.message);
    process.exit(1);
  });
