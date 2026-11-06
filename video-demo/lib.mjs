// Shared capture helpers: one forced-1080p browser logged in as the demo owner, CDP screencast -> constant-30fps frame index.
import { chromium } from "playwright";
import fs from "node:fs";
export const API = "http://127.0.0.1:8095", WEB = "http://127.0.0.1:3095"; // demo backend (MONGODB_DB=bcapp_demo) + flutter build/web
export const sleep = ms => new Promise(r => setTimeout(r, ms));
export const MGR = { w: 1440, h: 810, dsf: 1920 / 1440 }; // css viewport 1440x810 @1.3333 dpr -> screencast frames really are 1920x1080
// forced dpr (no emulation) is the only way CDP screencast returns true 1080p frames; window is oversized by the headless chrome offset
const FORCED = ["--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--force-device-scale-factor=1.333333", "--window-size=1466,909", "--hide-scrollbars"];
export const login = async email => (await fetch(API + "/api/auth/google", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email }) })).json();

export async function setup(email) {
  const b = await chromium.launch({ channel: "chrome", args: FORCED });
  const ctx = await b.newContext({ viewport: null });
  const { token, user } = await login(email);
  // the app keeps its session in shared_preferences (localStorage, values JSON-encoded)
  await ctx.addInitScript(([t, u]) => { localStorage.setItem("flutter.bcapp_jwt_token", JSON.stringify(t)); localStorage.setItem("flutter.bcapp_user_json", JSON.stringify(JSON.stringify(u))); }, [token, user]);
  return { m: await ctx.newPage(), token, close: () => b.close().catch(() => {}) };
}

// returns { stop(sceneDir, t_start, t_end) } ; arrival-time stamped so frames line up with the master clock t0 (ms)
export async function startRec(page, t0) {
  const cdp = await page.context().newCDPSession(page);
  const frames = []; let n = 0;
  cdp.on("Page.screencastFrame", ev => {
    const at = (Date.now() - t0) / 1000, file = `f${String(n++).padStart(6, "0")}.jpg`;
    frames.push({ at, file, data: ev.data });
    cdp.send("Page.screencastFrameAck", { sessionId: ev.sessionId }).catch(() => {});
  });
  await cdp.send("Page.startScreencast", { format: "jpeg", quality: 90, maxWidth: 1920, maxHeight: 1080, everyNthFrame: 1 });
  return {
    async stop(dir, t_start, t_end, fps = 30) {
      await cdp.send("Page.stopScreencast").catch(() => {}); await cdp.detach().catch(() => {});
      fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
      const used = new Set(), index = [];
      for (let k = 0, N = Math.ceil((t_end - t_start) * fps); k < N; k++) {
        const t = t_start + k / fps; let pick = frames[0];
        for (const f of frames) { if (f.at <= t) pick = f; else break; }
        index.push(pick.file); used.add(pick);
      }
      for (const f of used) fs.writeFileSync(`${dir}/${f.file}`, Buffer.from(f.data, "base64"));
      fs.writeFileSync(`${dir}/index.json`, JSON.stringify(index));
      return { captured: frames.length, used: used.size, out: index.length, at0: +(frames[0]?.at ?? 0).toFixed(1), at1: +(frames[frames.length - 1]?.at ?? 0).toFixed(1) };
    },
  };
}

// element box in 1920x1080 frame pixels (selector string or Locator)
export async function box(page, sel) {
  const l = typeof sel === "string" ? page.locator(sel).first() : sel;
  const b = await l.boundingBox({ timeout: 2500 });
  if (!b) return null;
  const k = MGR.dsf; return { x: Math.round(b.x * k), y: Math.round(b.y * k), w: Math.round(b.width * k), h: Math.round(b.height * k) };
}
