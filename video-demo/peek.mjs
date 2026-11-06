// Dev aid: open the web app logged in as EMAIL at 1440x810 and dump a screenshot + the
// Flutter semantics labels (so capture.mjs can target elements by text).
// node peek.mjs <out.jpg> [email] [clickText...]
import { chromium } from "playwright";
import fs from "node:fs";
const [out = "check/peek.jpg", email = "jead@bcapp.local", ...clicks] = process.argv.slice(2);
const API = "http://127.0.0.1:8095", WEB = "http://127.0.0.1:3095";
const login = await (await fetch(API + "/api/auth/google", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email }) })).json();
const b = await chromium.launch({ channel: "chrome" });
const p = await b.newPage({ viewport: { width: 1440, height: 810 } });
await p.addInitScript(([t, u]) => { localStorage.setItem("flutter.bcapp_jwt_token", JSON.stringify(t)); localStorage.setItem("flutter.bcapp_user_json", JSON.stringify(JSON.stringify(u))); }, [login.token, login.user]);
await p.goto(WEB);
await p.waitForTimeout(6000);
await p.locator("flt-semantics-placeholder").dispatchEvent("click").catch(() => {});
await p.waitForTimeout(800);
for (const c of clicks) {
  if (/^wait:\d+$/.test(c)) { await p.waitForTimeout(+c.slice(5)); continue; }
  if (c.startsWith("type:")) { await p.keyboard.type(c.slice(5), { delay: 20 }); await p.waitForTimeout(500); continue; }
  if (c.startsWith("key:")) { await p.keyboard.press(c.slice(4)); await p.waitForTimeout(1500); continue; }
  if (c.startsWith("scroll:")) { await p.mouse.move(900, 450); await p.mouse.wheel(0, +c.slice(7)); await p.waitForTimeout(1200); continue; }
  if (c.startsWith("shot:")) { await p.screenshot({ path: c.slice(5), type: "jpeg", quality: 70 }); continue; }
  if (/^\d+,\d+$/.test(c)) { const [x, y] = c.split(",").map(Number); await p.mouse.click(x, y); }
  else await p.getByText(c, { exact: false }).first().click({ timeout: 3000 }).catch(e => console.log("noclick", c));
  await p.waitForTimeout(2500);
}
fs.mkdirSync("check", { recursive: true });
await p.screenshot({ path: out, type: "jpeg", quality: 70 });
const labels = await p.evaluate(() => [...document.querySelectorAll("flt-semantics [role], flt-semantics span, flt-semantics")].map(e => {
  const r = e.getBoundingClientRect(), t = (e.getAttribute("aria-label") || e.textContent || "").trim().replace(/\s+/g, " ");
  return t && r.width > 0 ? `${e.getAttribute("role") || "-"}@${Math.round(r.x)},${Math.round(r.y)},${Math.round(r.width)}x${Math.round(r.height)} ${t.slice(0, 60)}` : null;
}).filter(Boolean));
console.log([...new Set(labels)].slice(0, 120).join("\n"));
await b.close();
