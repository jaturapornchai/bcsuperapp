// One continuous run on the master timeline (timeline.json); every click/keystroke lands on a narration word cue (C()).
// Flutter web on :3095 against the demo backend (MONGODB_DB=bcapp_demo) — run `node seed.mjs` first; the run mutates the demo data.
// Writes clips/<scene>/{index.json,cursor.json,f*.jpg} + boxes.json + facts.json + sfx.json.  ONLY=a,b  -> rehearse just those scenes.
import fs from "node:fs";
import { setup, startRec, sleep, box, login, API, WEB, MGR } from "./lib.mjs";
const tl = JSON.parse(fs.readFileSync("timeline.json", "utf8")), S = Object.fromEntries(tl.map(s => [s.id, s]));
const ONLY = process.env.ONLY ? process.env.ONLY.split(",") : null, on = id => !ONLY || ONLY.includes(id);
const R = JSON.parse(fs.readFileSync("rooms.json", "utf8"));
const { close, m, token: TW } = await setup("wichai@example.com");
const TK = (await login("tester1@bcapp.local")).token; // ก้อง ฝ่ายจัดส่ง claims the urgent job from "his phone"
const D = MGR.dsf, rdj = f => (fs.existsSync(f) && ONLY ? JSON.parse(fs.readFileSync(f, "utf8")) : null);
const boxes = rdj("boxes.json") || {}, facts = rdj("facts.json") || {};
// sfx: master-time click ("c") / key ("k") events for render.mjs; a rehearsal replaces only its own scenes' span
const inRehearsed = t => ONLY && ONLY.some(id => t >= S[id].start && t <= S[id].end + 0.3);
const sfx = (rdj("sfx.json") || []).filter(e => !inRehearsed(e.t));
let T0 = 0;
const T = () => (Date.now() - T0) / 1000;
const at = async t => { const w = t - T(); if (w > 0) await sleep(w * 1000); };
const ease = x => (x < 0.5 ? 2 * x * x : 1 - Math.pow(-2 * x + 2, 2) / 2);
const save = () => { fs.writeFileSync("boxes.json", JSON.stringify(boxes, null, 1)); fs.writeFileSync("facts.json", JSON.stringify(facts, null, 1)); fs.writeFileSync("sfx.json", JSON.stringify(sfx.sort((a, b) => a.t - b.t))); };
const C = (id, txt, off = 0) => { const s = S[id]; for (const c of [...s.cues.filter(c => c.d === txt), ...s.cues]) { /* exact chunk wins over a substring hit */ const i = c.d.indexOf(txt); if (i >= 0) return s.start + c.a + (c.b - c.a) * i / c.d.length + off; } throw new Error(`no cue ${id}:${txt}`); };
const api = async (method, path, tok, body) => { const r = await fetch(API + path, { method, headers: { "content-type": "application/json", authorization: "Bearer " + tok }, body: body ? JSON.stringify(body) : undefined }); if (!r.ok) console.log("  api", method, path, r.status); return r.json().catch(() => ({})); };

// --- cursor-logged mouse (headless frames carry no OS cursor; the video draws one from this track)
function driver(page, x = 700, y = 400) {
  const d = { page, x, y, track: [] };
  d.pt = (extra = {}) => d.track.push({ t: T(), x: d.x * D, y: d.y * D, ...extra });
  d.glide = async (tx, ty, dur = 700) => {
    const x0 = d.x, y0 = d.y, ts = Date.now();
    for (;;) { const k = Math.min(1, (Date.now() - ts) / dur), q = ease(k); d.x = x0 + (tx - x0) * q; d.y = y0 + (ty - y0) * q; await page.mouse.move(d.x, d.y); d.pt(); if (k >= 1) break; await sleep(8); }
  };
  d.click = async () => { d.pt({ click: 1 }); sfx.push({ t: +T().toFixed(3), k: "c" }); await page.mouse.down(); await sleep(70); await page.mouse.up(); };
  d.center = async sel => { if (sel && sel.x != null) return sel; try { const b = await sel.boundingBox({ timeout: 2500 }); return b && { x: b.x + b.width / 2, y: b.y + b.height / 2, b }; } catch { return null; } };
  d.clickAt = async (t, sel, dur = 900) => { dur = Math.max(250, Math.min(dur, (t - 0.25 - T()) * 1000)); await at(t - dur / 1000 - 0.15); const c = await d.center(sel); if (!c) { console.log("  missing", String(sel).slice(0, 90)); return false; } await d.glide(c.x, c.y, dur); await at(t - 0.08); await d.click(); const late = T() - t; if (late > 0.35) console.log("  LATE", late.toFixed(1), "@", t.toFixed(1), String(sel).slice(0, 70)); return true; };
  d.hoverAt = async (t, sel, dur = 900) => { await at(t - dur / 1000); const c = await d.center(sel); if (c) await d.glide(c.x, c.y, dur); else console.log("  nohover", String(sel).slice(0, 70)); return !!c; };
  return d;
}
const M = driver(m, 760, 420);

async function grab(name, sel) { const t0 = T(); try { const b = await box(m, sel); if (b) boxes[name] = b; else console.log("  nobox", name); } catch { console.log("  nobox", name); } if (T() - t0 > 1) console.log("  slowgrab", name, (T() - t0).toFixed(1)); }
const rect = (name, x, y, w, h) => { boxes[name] = { x: Math.round(x * D), y: Math.round(y * D), w: Math.round(w * D), h: Math.round(h * D) }; };
async function scene(id, fn) {
  if (!on(id)) return;
  const s = S[id]; await at(s.start); M.track = []; M.pt();
  const rec = await startRec(m, T0), tEnd = s.end + 0.3;
  try { await fn(s); } catch (err) { console.log("scene error", id, String(err.message).slice(0, 220)); }
  await at(tEnd);
  const r = await rec.stop(`clips/${id}`, s.start, tEnd);
  fs.writeFileSync(`clips/${id}/cursor.json`, JSON.stringify(M.track.filter(p => p.t >= s.start && p.t <= tEnd).map(p => ({ ...p, t: +(p.t - s.start).toFixed(3) }))));
  save(); console.log(id, JSON.stringify(r), "t=", T().toFixed(1));
}

// --- locators: Flutter semantics (buttons/groups/menuitems by accessible name, text fields by aria-label)
const vis = l => l.filter({ visible: true }).first();
const btn = name => vis(m.getByRole("button", { name }));
const room = name => btn(new RegExp(name));
const msg = re => m.getByRole("group", { name: re }).filter({ visible: true }).last();
const inMsg = (re, name) => msg(re).getByRole("button", { name });
const field = re => vis(m.getByLabel(re));
const txt = t => vis(m.getByText(t));
// composer: its aria-label is the hint, which disappears once it holds text -> click by position
const COMPOSER = { x: 1000, y: 778 }, DRAFT = /^ข้อความร่างของคุณ/, SEND = { x: 1407, y: 778 };
const G1 = "ทีมขาย-คลัง-จัดส่ง", G2 = "บัญชี-การเงิน", DS = "สมชาย ผู้จัดการขาย", DA = "BC AI ผู้ช่วยอัจฉริยะ";
const nav = name => vis(m.getByRole("button", { name: new RegExp(`(^|\\s)${name}$`) }));
const waitVis = (loc, ms) => loc.waitFor({ state: "visible", timeout: ms }).then(() => true, () => false);
const lastMsg = async roomId => { const r = await api("GET", `/api/conversations/${roomId}/messages`, TW); const a = Array.isArray(r) ? r : r.messages || []; return a[a.length - 1] || {}; };
async function waitAi(roomId, beforeId, ms = 45000) { for (const t = Date.now(); Date.now() - t < ms; await sleep(400)) { const l = await lastMsg(roomId); if (l.sender_id === "user_ai" && l.id !== beforeId) return l; } console.log("  no AI reply in", roomId); return {}; }
// smooth wheel scroll at a point (Flutter scroll views only react to wheel / drag)
async function wheel(x, y, dy, dur = 700) { await M.glide(x, y, 350); const n = 14; for (let i = 0; i < n; i++) { await m.mouse.wheel(0, dy / n); await sleep(dur / n); } }
// click a field at t, optionally select-all, then type like a person (each key logged for the keyboard sfx)
async function typeAt(t, loc, text, cps = 13, { mv = 500, gap = 0.55, replace = true } = {}) {
  t = Math.max(t, T() + gap);
  if (!(await M.clickAt(t, loc, mv))) return; // typing into whatever holds focus could press a button
  await sleep(150);
  if (replace) { await m.keyboard.press("Control+A"); sfx.push({ t: +T().toFixed(3), k: "k" }); await sleep(120); }
  else await m.keyboard.press("End");
  for (const ch of text) { await m.keyboard.type(ch); sfx.push({ t: +T().toFixed(3), k: "k" }); await sleep((1000 / cps) * (0.7 + Math.random() * 0.6)); }
}
const aiText = () => vis(m.locator("textarea")).inputValue({ timeout: 1500 }).catch(() => "");
const say = async loc => (await loc.innerText({ timeout: 1500 }).catch(() => "")).replace(/\s+/g, " ").trim();

// ---- prep (not recorded) -------------------------------------------------------------------------------------------
m.setDefaultTimeout(6000);
await m.goto(WEB, { waitUntil: "domcontentloaded", timeout: 120000 });
await sleep(6000);
await m.locator("flt-semantics-placeholder").dispatchEvent("click").catch(() => {});
await room(G1).waitFor({ timeout: 60000 }); await sleep(1500);
await m.mouse.move(M.x, M.y);
// rehearsal: walk straight to the state the first requested scene expects
const PREP = { task: G1, atai: G1, polish: DS, plan: DS, translate: DS, purge: G1, vault: G1, handover: null };
if (ONLY && PREP[ONLY[0]]) { await room(PREP[ONLY[0]]).click(); await sleep(1500); if (ONLY[0] === "translate") { await btn("AI เกลาคำพูด").click(); await sleep(1500); } }
if (ONLY && ["admin", "handover"].includes(ONLY[0])) { await nav("หลังบ้าน").click(); await sleep(2000); }
T0 = Date.now() + 1000 - (ONLY ? S[ONLY[0]].start * 1000 : 0);

// ---- hook: the chat screen drifts by under the kinetic title (announcement room is open on launch)
await scene("hook", async s => {
  await M.hoverAt(C("hook", "แชทงานปนกับแชทส่วนตัว"), room(DS), 1200);
  await M.hoverAt(C("hook", "ข้อความในกลุ่มเด้งเป็นร้อย"), room(G1), 900);
  await M.hoverAt(C("hook", "สั่งงานไปแล้ว"), btn("กดรับงานนี้"), 900);
  await M.hoverAt(C("hook", "ส่งไฟล์ลับผิดห้อง"), btn("จัดการข้อความ / ส่งผิดลบได้"), 900);
  await M.glide(960, 470, 1500);
});

// ---- home: nav rail, room list, tabs, pins, unread badge, watermark
await scene("home", async s => {
  rect("nav", 4, 100, 76, 300); rect("list", 84, 172, 389, 302); rect("tabs", 92, 119, 381, 48); rect("wm", 1240, 60, 200, 74);
  await grab("unread", txt(/^ยังไม่อ่าน \d+$/)); await grab("g1item", room(G1)); await grab("shield", btn("เปิดลายน้ำนิรภัย"));
  await M.hoverAt(C("home", "ชื่อสมใจค้าส่ง"), room("ประกาศ สมใจค้าส่ง"), 900);
  await M.hoverAt(C("home", "แถบซ้ายสุดคือเมนูหลัก"), nav("หน้าหลัก"), 800);
  await M.hoverAt(C("home", "แถบซ้ายสุดคือเมนูหลัก", 1.2), nav("หลังบ้าน"), 900);
  await M.hoverAt(C("home", "ถัดมาคือรายการห้องแชท"), room(G2), 800);
  for (const [w, t] of [["ทั้งหมด", "ทั้งหมด"], ["ส่วนตัว", "ส่วนตัว"], ["เรื่องงาน", "เรื่องงาน"], ["กลุ่ม", "กลุ่ม"], ["และปักหมุด", "ปักหมุด"]]) await M.hoverAt(C("home", w), vis(m.getByRole("button", { name: t, exact: true })), 450);
  await M.hoverAt(C("home", "ห้องสำคัญปักหมุดไว้ด้านบน"), room(G1), 700);
  await M.hoverAt(C("home", "ส่วนป้ายด้านบน"), txt(/^ยังไม่อ่าน \d+$/), 800);
  await M.hoverAt(C("home", "มุมขวาบนมีลายน้ำ"), btn("เปิดลายน้ำนิรภัย"), 900);
  await M.hoverAt(C("home", "ชื่อและอีเมล"), { x: 1330, y: 98 }, 800);
});

// ---- summary: AI reads the whole busy group and splits it into points / to-dos with owners / decisions
await scene("summary", async s => {
  await M.clickAt(C("summary", "มาดูห้องกลุ่ม"), room(G1), 800); await sleep(1200);
  rect("chatArea", 476, 120, 962, 590);
  await at(C("summary", "ทั้งลูกค้าขอส่วนลด")); await wheel(900, 420, -900, 1600);
  await at(C("summary", "ถ้าต้องไล่อ่านทีละข้อความ")); await wheel(900, 420, 1400, 1200);
  await grab("sumBtn", btn("AI สรุปแชท & แกะงาน"));
  const t1 = C("summary", "AI สรุปแชท"); await M.clickAt(t1, btn("AI สรุปแชท & แกะงาน"), 900);
  const keep = btn("บันทึกเข้า BC Keep");
  if (!(await waitVis(keep, 30000))) console.log("  no summary");
  facts.summaryLatency = +(T() - t1).toFixed(1); console.log("  summary ready after", facts.summaryLatency, "s");
  await sleep(400); await grab("sumKey", txt("สรุปประเด็นสำคัญในห้องแชท"));
  await M.hoverAt(C("summary", "ส่วนแรก"), txt("สรุปประเด็นสำคัญในห้องแชท"), 700);
  await at(C("summary", "ส่วนที่สอง", -0.6)); await wheel(720, 420, 330, 700); await sleep(300);
  await grab("sumTodo", txt("รายการงานที่ต้องทำต่อ"));
  await M.hoverAt(C("summary", "ส่วนที่สอง", 0.3), txt("รายการงานที่ต้องทำต่อ"), 600);
  await M.glide(940, 520, 900);
  await at(C("summary", "และส่วนที่สาม", -0.6)); await wheel(720, 420, 600, 800); await sleep(300);
  await grab("sumDec", txt("ข้อตกลงและการตัดสินใจ"));
  await M.hoverAt(C("summary", "และส่วนที่สาม", 0.3), txt("ข้อตกลงและการตัดสินใจ"), 600);
  await grab("keepBtn", keep);
  await M.clickAt(C("summary", "กดบันทึกเข้า", 0.5), keep, 800);
});

// ---- task: ก้อง claims the urgent job (from his own device = API), every screen updates live
await scene("task", async s => {
  const U = /ด่วนพิเศษ/;
  if (await btn("บันทึกเข้า BC Keep").isVisible().catch(() => false)) { await m.keyboard.press("Escape"); await sleep(600); }
  const msgs = await api("GET", `/api/conversations/${R.G1}/messages?limit=100`, TW);
  const urgent = (Array.isArray(msgs) ? msgs : msgs.messages || []).find(x => String(x.content || "").startsWith("ด่วน! ร้านเจริญผล"));
  if (!urgent) console.log("  no urgent message id");
  await grab("urgent", msg(U)); await grab("claim", inMsg(U, "กดรับงานนี้"));
  await M.hoverAt(C("task", "มีปุ่มรับงานติดอยู่ใต้ข้อความ"), inMsg(U, "กดรับงานนี้"), 900);
  await M.hoverAt(C("task", "อย่างงานด่วนนี้"), msg(U), 800);
  await at(C("task", "กดรับงาน")); if (urgent) await api("POST", `/api/messages/${urgent.id}/task-action`, TK, { action: "accept" });
  await sleep(1500); await grab("claim2", txt(/รับงานโดย/));
  await M.hoverAt(C("task", "แถบใต้ข้อความก็เปลี่ยนเป็น"), txt(/รับงานโดย/), 700);
  await at(C("task", "กดอีกครั้ง")); if (urgent) await api("POST", `/api/messages/${urgent.id}/task-action`, TK, { action: "done" });
  await sleep(1500); await grab("claim3", txt(/ดำเนินการเสร็จสิ้นโดย/)); boxes.claim3 ||= boxes.claim2; // same bar, new wording
});

// ---- atai: "@ai" question in the group, the answer lands in the room for everyone
await scene("atai", async s => {
  await grab("atChip", btn("@ai ถามสมองกลในกลุ่ม"));
  await M.clickAt(C("atai", "@ai ถามสมองกล"), btn("@ai ถามสมองกลในกลุ่ม"), 900);
  await typeAt(C("atai", "แล้วพิมพ์คำถาม"), COMPOSER, "งานด่วนที่ยังค้างอยู่มีอะไรบ้าง ใครต้องทำ", 14, { replace: false });
  const id0 = (await lastMsg(R.G1)).id, t1 = C("atai", "แล้วกดส่ง");
  await M.clickAt(t1, SEND, 600);
  facts.atai = ((await waitAi(R.G1, id0)).content || "").slice(0, 900);
  facts.ataiLatency = +(T() - t1).toFixed(1); console.log("  @ai reply after", facts.ataiLatency, "s");
  await sleep(1200); await grab("ataiReply", msg(/BC AI ผู้ช่วยอัจฉริยะ/));
  await M.hoverAt(Math.max(T() + 0.8, C("atai", "ก็ตอบกลับเข้ามาในกลุ่ม")), msg(/BC AI ผู้ช่วยอัจฉริยะ/), 800);
});

// ---- assist dialog: suggest / polish / plan / translate (DS room)
const RESULT = () => vis(m.locator("textarea")), dlgResult = name => grab(name, RESULT());
await scene("suggest", async s => {
  await M.clickAt(C("suggest", "ต่อไปเป็นแชทส่วนตัวกับสมชาย"), room(DS), 900); await sleep(1500);
  await grab("dsAsk", msg(/สมชาย ผู้จัดการขาย/));
  await M.hoverAt(C("suggest", "สมชายถามว่า"), msg(/สมชาย ผู้จัดการขาย/), 800);
  await grab("sugChip", btn("คิดคำตอบด่วนจากแชทล่าสุด"));
  const t1 = C("suggest", "คิดคำตอบด่วน"); await M.clickAt(t1, btn("คิดคำตอบด่วนจากแชทล่าสุด"), 900);
  await waitVis(btn("ส่งเข้าห้องแชททันที"), 30000); await sleep(4000);
  await dlgResult("sugRes"); facts.suggest = (await aiText()).slice(0, 900);
  await M.hoverAt(C("suggest", "แล้วร่างคำตอบ"), RESULT(), 800);
  await M.clickAt(C("suggest", "กดนำไปใส่ช่องพิมพ์", 0.4), btn("นำไปใส่ช่องพิมพ์"), 900);
});
await scene("polish", async s => {
  await typeAt(C("polish", "ว่า"), COMPOSER, "ลด 3% ไม่ได้ ให้ได้ 2% ถ้าจ่ายสด บอกเจ๊หมวยด้วย", 13);
  rect("draft", 600, 758, 800, 40);
  const t1 = C("polish", "AI เกลาคำพูด"); await M.clickAt(t1, btn("AI เกลาคำพูด"), 800);
  await waitVis(btn("ส่งเข้าห้องแชททันที"), 30000); await sleep(3500);
  await dlgResult("polRes"); facts.polish = (await aiText()).slice(0, 700);
  await M.hoverAt(C("polish", "ก็เรียบเรียงใหม่"), RESULT(), 800);
  await M.clickAt(C("polish", "กดส่งเข้าห้องแชททันที", 0.3), btn("ส่งเข้าห้องแชททันที"), 900);
  await sleep(1500); await grab("polSent", msg(/^(พนักงานองค์กร|อ่านแล้ว|ส่งแล้ว)/) /* own bubbles carry no sender name */);
  await M.hoverAt(C("polish", "ข้อความก็ส่งถึงสมชาย"), { x: 1000, y: 560 }, 700);
  // the rough draft is still in the composer; clear it so the next dialog starts clean
  await m.mouse.click(COMPOSER.x, COMPOSER.y); await m.keyboard.press("Control+A"); await m.keyboard.press("Backspace");
});
await scene("plan", async s => {
  await M.clickAt(s.start + 0.9, btn("AI เกลาคำพูด"), 800); await sleep(1200);
  await typeAt(C("plan", "พิมพ์เป้าหมายลงในช่องร่างข้อความ"), field(DRAFT), "เดือนนี้ต้องเปิดลูกค้ามินิมาร์ทใหม่ 10 ร้าน", 14);
  await grab("modes", vis(m.getByRole("checkbox", { name: "เกลาให้สุภาพเป็นทางการ" })));
  await M.clickAt(C("plan", "แล้วเลือกโหมดแปลงเป็นแผนงาน", 0.6), vis(m.getByRole("checkbox", { name: /แปลงเป็นแผนงาน/ })), 800);
  await grab("planChip", vis(m.getByRole("checkbox", { name: /แปลงเป็นแผนงาน/ })));
  await sleep(6000); await dlgResult("planRes"); facts.plan = (await aiText()).slice(0, 900);
  await M.hoverAt(C("plan", "เป็นขั้นตอนทีละข้อ"), RESULT(), 800);
});
await scene("translate", async s => {
  await typeAt(C("translate", "พิมพ์ภาษาไทย"), field(DRAFT), "ขอใบเสนอราคาน้ำมันปาล์ม 1,000 ลัง ส่งภายในสิ้นเดือนนี้", 15);
  await M.clickAt(C("translate", "แล้วเลือกโหมดแปล", 0.6), vis(m.getByRole("checkbox", { name: /แปลเป็นภาษาอังกฤษธุรกิจ/ })), 800);
  await grab("trChip", vis(m.getByRole("checkbox", { name: /แปลเป็นภาษาอังกฤษธุรกิจ/ })));
  await sleep(5500); await dlgResult("trRes"); facts.translate = (await aiText()).slice(0, 700);
  await M.hoverAt(C("translate", "ก็ได้ข้อความภาษาอังกฤษ"), RESULT(), 800);
});

// ---- aichat: private room with the AI assistant
await scene("aichat", async s => {
  await m.keyboard.press("Escape"); await sleep(500);
  await M.clickAt(C("aichat", "ทุกคนยังมีห้องแชทส่วนตัว"), room(DA), 900); await sleep(1200);
  await typeAt(C("aichat", "เช่น"), COMPOSER, "ช่วยร่างข้อความทวงเงินร้านโชคดีพาณิชย์ ยอด 45,600 บาท แบบสุภาพ", 16);
  const id0 = (await lastMsg(R.DA)).id, t1 = C("aichat", "ส่งไปแล้วรอสักครู่"); await M.clickAt(t1, SEND, 600);
  facts.aichat = ((await waitAi(R.DA, id0)).content || "").slice(0, 1200);
  facts.aichatLatency = +(T() - t1).toFixed(1); console.log("  ai room reply after", facts.aichatLatency, "s");
  await sleep(1200); await grab("aiReply", msg(/BC AI ผู้ช่วยอัจฉริยะ/));
  await M.hoverAt(Math.max(T() + 0.8, C("aichat", "ก็ตอบกลับมาในห้อง")), msg(/BC AI ผู้ช่วยอัจฉริยะ/), 800);
});

// ---- approve: purchase card approved inside the chat
await scene("approve", async s => {
  await M.clickAt(C("approve", "ห้องบัญชีการเงิน"), room(G2), 900); await sleep(1500);
  await grab("invoice", msg(/ใบแจ้งหนี้_INV/)); await grab("card", msg(/ขออนุมัติสั่งซื้อ/));
  await M.hoverAt(C("approve", "มีทั้งใบแจ้งหนี้จากนิดา"), msg(/ใบแจ้งหนี้_INV/), 800);
  await M.hoverAt(C("approve", "และการ์ดขออนุมัติสั่งซื้อจากบอส"), msg(/ขออนุมัติสั่งซื้อ/), 800);
  await grab("approveBtn", btn("อนุมัติทันที"));
  await M.clickAt(C("approve", "กดอนุมัติทันทีได้ในแชท", 0.4), btn("อนุมัติทันที"), 900);
  await sleep(1500); await grab("card2", msg(/ขออนุมัติสั่งซื้อ/));
});

// ---- purge: a payroll file lands in the sales group by mistake -> recalled and destroyed in storage
await scene("purge", async s => {
  await M.clickAt(s.start + 1.2, room(G1), 900); await sleep(800);
  await at(C("purge", "เช่น", -0.3));
  const f = "เงินเดือนพนักงาน_ตุลาคม.pdf", att = await api("POST", "/api/upload", TW, { file_name: f, mime_type: "application/pdf", data_base64: fs.readFileSync("assets/" + f).toString("base64") });
  await api("POST", `/api/conversations/${R.G1}/messages`, TW, { type: "file", content: f, attachment: att });
  facts.purgeUrl = att.url || att.file_url || "";
  const F = /เงินเดือนพนักงาน_ตุลาคม/;
  if (!(await waitVis(msg(F), 4000))) { await wheel(900, 520, 4000, 500); await waitVis(msg(F), 4000); } await sleep(600); await grab("payroll", msg(F));
  await M.hoverAt(C("purge", "หลุดเข้ากลุ่มทีมขาย"), msg(F), 800);
  await M.clickAt(C("purge", "กดเมนูสามจุดที่ข้อความ", 0.6), inMsg(F, "จัดการข้อความ / ส่งผิดลบได้"), 900);
  await sleep(500); await grab("purgeItem", vis(m.getByRole("menuitem", { name: /ยกเลิกข้อความ & ลบไฟล์ทันที/ })));
  await M.clickAt(C("purge", "แล้วเลือก", 0.5), vis(m.getByRole("menuitem", { name: /ยกเลิกข้อความ & ลบไฟล์ทันที/ })), 800);
  await sleep(1200); facts.purgeGone = !(await msg(F).isVisible().catch(() => false));
});

// ---- vault + in-room search
await scene("vault", async s => {
  await M.clickAt(C("vault", "ระบบเก็บไว้ให้ในคลังรูปและไฟล์ถาวร", 0.3), btn("คลังรูป & ไฟล์ถาวร"), 900); await sleep(1000);
  const tab = t => vis(m.getByRole("tab", { name: t }));
  await grab("vTabs", tab(/^รูปภาพ/)); await M.hoverAt(C("vault", "รูปภาพ"), tab(/^รูปภาพ/), 600);
  await M.clickAt(C("vault", "ไฟล์เอกสาร"), tab(/^ไฟล์เอกสาร/), 600);
  await M.clickAt(C("vault", "และโน้ตประจำห้อง"), tab(/^โน้ตประจำห้อง/), 600);
  await at(C("vault", "ย้อนไปหาเมื่อไหร่ก็เจอ", 1.0)); await m.keyboard.press("Escape"); await sleep(500);
  await grab("searchBtn", btn("ค้นหาข้อความในห้องนี้"));
  await M.clickAt(C("vault", "ส่วนปุ่มแว่นขยายด้านบน", 0.5), btn("ค้นหาข้อความในห้องนี้"), 900); await sleep(600);
  await grab("searchBox", field(/^ค้นหาข้อความ ชื่อไฟล์/)); // its label is the hint: gone once typed
  await typeAt(C("vault", "พิมพ์คำว่า"), field(/^ค้นหาข้อความ ชื่อไฟล์/), "โชคดี", 8);
  await sleep(1500); await grab("searchHit", msg(/นิดา ฝ่ายบัญชี/)); // groups are named by sender
  await M.hoverAt(C("vault", "ก็เจอข้อความ"), { x: 900, y: 450 }, 800);
});

// ---- keep: the saved AI summary next to the other notes
await scene("keep", async s => {
  if (await btn("ปิด").isVisible().catch(() => false)) await btn("ปิด").click();
  await M.clickAt(C("keep", "BC Keep"), nav("BC Keep"), 900); await sleep(1500);
  await grab("kSum", txt(/AI สรุปห้อง/)); await grab("kBang", txt("ลูกค้าสายบางบัวทอง")); await grab("kGoal", txt("เป้ายอดขายเดือนนี้"));
  await M.hoverAt(C("keep", "สรุปจาก"), txt(/AI สรุปห้อง/), 800);
  await M.hoverAt(C("keep", "รายชื่อลูกค้าสายบางบัวทอง"), txt("ลูกค้าสายบางบัวทอง"), 700);
  await M.hoverAt(C("keep", "และเป้ายอดขายเดือนนี้"), txt("เป้ายอดขายเดือนนี้"), 700);
});

// ---- admin: stats, theme, DeepSeek settings (key masked)
await scene("admin", async s => {
  await M.clickAt(C("admin", "มีหน้าหลังบ้าน"), nav("หลังบ้าน"), 900); await sleep(1500);
  rect("stats", 200, 78, 1066, 106); rect("themes", 203, 206, 1118, 244);
  await M.hoverAt(C("admin", "ด้านบนเป็นสถิติการใช้งาน"), { x: 600, y: 125 }, 800);
  await M.hoverAt(C("admin", "ถัดมาเลือกธีมสี"), btn(/แดงทับทิมค้าปลีก/), 800);
  await at(C("admin", "ส่วนนี้คือการตั้งค่า", -0.8)); await wheel(760, 500, 300, 700); await sleep(400);
  await grab("dsCard", txt(/ตั้งค่าสมองกล DeepSeek AI ประจำองค์กร/)); await grab("model", vis(m.getByRole("checkbox", { name: /deepseek-chat/ })));
  await grab("apiKey", txt(/^API Key: sk-/)); await grab("sysPrompt", field(/^System Prompt/));
  await M.hoverAt(C("admin", "เลือกรุ่นสมองกลได้"), vis(m.getByRole("checkbox", { name: /deepseek-chat/ })), 700);
  await M.hoverAt(C("admin", "คีย์ถูกซ่อนไว้"), txt(/^API Key: sk-/), 700);
  await M.hoverAt(C("admin", "และเขียนคำสั่งตั้งต้นได้"), field(/^System Prompt/), 700);
});

// ---- handover: แพร leaves, มายด์ takes over every room, AI briefs her in each one
await scene("handover", async s => {
  await at(s.start + 0.4); await wheel(760, 500, 520, 900); await sleep(500);
  const from = btn(/^พนักงานต้นทาง/), to = btn(/^พนักงานผู้รับมอบงานคนใหม่/), go = btn(/^โอนย้ายห้องแชท & สร้างสรุปงานด้วย AI/);
  await grab("hoFrom", from); await grab("hoTo", to); await grab("hoGo", go);
  await M.clickAt(C("handover", "เลือกแพรเป็นพนักงานต้นทาง", -0.3), from, 800); await sleep(700);
  await M.clickAt(C("handover", "เลือกแพรเป็นพนักงานต้นทาง", 0.9), vis(m.getByRole("menuitem", { name: /แพร พนักงานขาย/ })), 500); await sleep(500);
  await M.clickAt(C("handover", "เลือกมายด์", -0.2), to, 700); await sleep(700);
  await M.clickAt(C("handover", "เลือกมายด์", 1.0), vis(m.getByRole("menuitem", { name: /มายด์ พนักงานขาย/ })), 500); await sleep(500);
  const t1 = C("handover", "แล้วกดโอนย้าย", 0.3); await M.clickAt(t1, go, 800);
  const snack = txt(/โอนย้ายห้องแชทสำเร็จ/);
  await waitVis(snack, 30000); facts.handoverLatency = +(T() - t1).toFixed(1); facts.handover = await say(snack); console.log("  handover", facts.handover, facts.handoverLatency, "s");
  await M.clickAt(Math.max(T() + 1, C("handover", "เปิดห้องทีมขายดู")), nav("แชท"), 700); await sleep(1200);
  await M.clickAt(T() + 0.9, room(G1), 700); await sleep(1500);
  await grab("brief", msg(/BC AI ผู้ช่วยอัจฉริยะ/));
  await M.hoverAt(Math.max(T() + 0.6, C("handover", "มายด์อ่านแล้ว")), msg(/BC AI ผู้ช่วยอัจฉริยะ/), 800);
  facts.brief = ((await lastMsg(R.G1)).content || "").slice(0, 1200);
});

// ---- mini apps
await scene("miniapps", async s => {
  await M.clickAt(C("miniapps", "สุดท้าย", 0.3), nav("บริการเสริม"), 900); await sleep(1200);
  for (const [w, t, k] of [["อนุมัติใบลา", "อนุมัติใบลา / งานบุคคล", "maLeave"], ["ออกใบเสนอราคาด่วน", "ออกใบเสนอราคาด่วน", "maQuote"], ["เบิกค่าใช้จ่าย", "เบิกค่าใช้จ่าย / แนบบิล", "maClaim"], ["และจองคิว", "จองคิว / นัดหมายลูกค้า", "maBook"]]) {
    await grab(k, txt(t)); await M.hoverAt(C("miniapps", w), txt(t), 600);
  }
  rect("maGrid", 222, 196, 1052, 406);
  await M.clickAt(C("miniapps", "กรอกแล้วส่งเป็นการ์ดเข้าห้อง", -0.2), m.getByRole("button", { name: "เปิดใช้งาน & ส่งการ์ด" }).nth(1), 800); await sleep(1500);
  rect("maForm", 260, 146, 491, 568); rect("maPreview", 770, 146, 410, 316);
  await M.hoverAt(C("miniapps", "ให้หัวหน้ากดอนุมัติ"), { x: 975, y: 330 }, 800);
});

if (!ONLY) await at(S.benefits.start);
save(); await close();
console.log("DONE", JSON.stringify(facts).slice(0, 2500));
