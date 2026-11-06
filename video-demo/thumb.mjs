// thumb.html + a real composed still -> thumbnail.jpg (1280x720 YouTube thumbnail)
// node thumb.mjs check/t120.jpg
import { chromium } from "playwright";
import path from "node:path";
const bg = process.argv[2], b = await chromium.launch({ channel: "chrome" }), p = await b.newPage({ viewport: { width: 1280, height: 720 } });
await p.goto("file:///" + path.resolve("thumb.html").replace(/\\/g, "/") + "?bg=" + encodeURIComponent(bg));
await p.evaluate(async () => { await document.fonts.ready; await document.images[0].decode(); });
await p.screenshot({ path: "thumbnail.jpg", type: "jpeg", quality: 92 }); await b.close();
