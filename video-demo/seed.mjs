// Demo world for the video: fictional wholesaler "บริษัท สมใจค้าส่ง จำกัด" in the bcapp_demo DB.
// Re-runnable: wipes every room except the 5-tester room, then rebuilds rooms/messages through
// the API (so last_message/read flags are real) and back-dates them to this morning.
// Needs the backend on :8095 started with MONGODB_DB=bcapp_demo (refuses otherwise).
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import fs from "node:fs";

const API = "http://127.0.0.1:8095";
const mongo = (js) => execFileSync("docker", ["exec", "-i", "bcapp-mongodb", "mongosh", "bcapp_demo", "--quiet"], { input: js }).toString().trim();

// Guard: the API calls below must never land in the dev DB (bcapp). Write a nonce into
// bcapp_demo and check that the running backend hands it back.
const nonce = "demo-" + Date.now();
mongo(`db.users.updateOne({ _id: "user_official" }, { $set: { status_message: "${nonce}" } })`);
const probe = await (await fetch(API + "/api/auth/google", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email: "official.bc@bcapp.local" }) })).json();
if (probe.user?.status_message !== nonce) throw new Error("backend on :8095 is not using bcapp_demo — stop");

// ---------- 1. cast ----------
const CAST = {
  user_jead: ["วิชัย (เจ้าของกิจการ)", "บริหาร", "เจ้าของกิจการ", "wichai@example.com"],
  user_somchai: ["สมชาย ผู้จัดการขาย", "ฝ่ายขาย", "ผู้จัดการฝ่ายขาย"],
  user_nida: ["นิดา ฝ่ายบัญชี", "บัญชีและการเงิน", "หัวหน้าฝ่ายบัญชี"],
  user_tester5: ["ต้น คลังสินค้า", "คลังสินค้า", "หัวหน้าคลังสินค้า"],
  user_tester2: ["แพร พนักงานขาย", "ฝ่ายขาย", "พนักงานขาย"],
  user_tester4: ["มายด์ พนักงานขาย", "ฝ่ายขาย", "พนักงานขาย"],
  user_tester1: ["ก้อง ฝ่ายจัดส่ง", "จัดส่ง", "หัวหน้าจัดส่ง"],
  user_tester3: ["บอส จัดซื้อ", "จัดซื้อ", "เจ้าหน้าที่จัดซื้อ"],
  user_official: ["ประกาศ สมใจค้าส่ง", "สำนักงาน", "ช่องทางประกาศบริษัท"],
  user_ai: ["🤖 BC AI ผู้ช่วยอัจฉริยะ", "AI Brain", "ผู้ช่วยประจำทุกคนและทุกกลุ่ม"],
};
const KEEP_ROOM = "conv_group_test5";
mongo(`
const cast = ${JSON.stringify(CAST)};
for (const [id, [name, dept, title, email]] of Object.entries(cast)) {
  const set = { display_name: name, department: dept, job_title: title, avatar_url: "", status_message: "" };
  if (email) set.email = email;
  db.users.updateOne({ _id: id }, { $set: set });
}
const keep = ${JSON.stringify(KEEP_ROOM)};
db.messages.deleteMany({ conversation_id: { $ne: keep } });
db.conversations.deleteMany({ _id: { $ne: keep } });
db.files.deleteMany({ conversation_id: { $ne: keep } });
db.notes.deleteMany({});
`);

// ---------- 2. helpers ----------
async function req(method, path, token, body) {
  const r = await fetch(API + path, { method, headers: { "content-type": "application/json", ...(token ? { authorization: "Bearer " + token } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const t = await r.text();
  if (!r.ok) throw new Error(`${method} ${path} -> ${r.status} ${t.slice(0, 200)}`);
  return t ? JSON.parse(t) : null;
}
async function tokenFor(email) { return (await req("POST", "/api/auth/google", null, { email })).token; }
const EMAIL = { W: "wichai@example.com", S: "somchai.sales@bcapp.local", N: "nida.acc@bcapp.local", T: "tester5@bcapp.local", P: "tester2@bcapp.local", M: "tester4@bcapp.local", K: "tester1@bcapp.local", B: "tester3@bcapp.local", O: "official.bc@bcapp.local", A: "ai@bcapp.local" };
const ID = { W: "user_jead", S: "user_somchai", N: "user_nida", T: "user_tester5", P: "user_tester2", M: "user_tester4", K: "user_tester1", B: "user_tester3", O: "user_official", A: "user_ai" };
const TOK = {};
for (const [k, e] of Object.entries(EMAIL)) TOK[k] = await tokenFor(e);
// Logging in runs onboarding, which leaves a sample note with made-up company details.
mongo("db.notes.deleteMany({});");

// ---------- 3. files rendered by Chromium (fictional documents) ----------
fs.mkdirSync("assets", { recursive: true });
const DOC_CSS = `body{font-family:'Leelawadee UI',Tahoma,sans-serif;color:#1e293b;margin:0;padding:36px 44px;font-size:14px}
h1{font-size:22px;margin:0 0 4px;color:#047857}.co{font-size:13px;color:#475569;margin-bottom:18px}
table{width:100%;border-collapse:collapse;margin-top:12px}th,td{border:1px solid #cbd5e1;padding:8px 10px;text-align:left}
th{background:#ecfdf5}td.n{text-align:right}.tot{font-weight:700;background:#f8fafc}.warn{color:#b91c1c;font-weight:700}
.meta{display:flex;justify-content:space-between;font-size:13px}.foot{margin-top:22px;font-size:12px;color:#64748b}`;
const docs = [
  ["ใบเสนอราคา_QT-0014_ร้านเจ๊หมวย.pdf", "application/pdf", `<h1>ใบเสนอราคา</h1><div class="co">บริษัท สมใจค้าส่ง จำกัด (ข้อมูลสมมติสำหรับสาธิต)</div>
   <div class="meta"><div>ลูกค้า: ร้านเจ๊หมวย<br>ผู้เสนอราคา: แพร พนักงานขาย</div><div>เลขที่ QT-0014<br>ยืนราคา 15 วัน</div></div>
   <table><tr><th>รายการ</th><th>จำนวน</th><th>ราคา/หน่วย</th><th>รวม (บาท)</th></tr>
   <tr><td>น้ำดื่ม 600 มล. (แพ็ค 12 ขวด)</td><td>100 แพ็ค</td><td class="n">52.00</td><td class="n">5,200.00</td></tr>
   <tr><td>บะหมี่กึ่งสำเร็จรูป (ลัง 30 ซอง)</td><td>50 ลัง</td><td class="n">165.00</td><td class="n">8,250.00</td></tr>
   <tr class="tot"><td colspan="3">รวมเป็นเงิน</td><td class="n">13,450.00</td></tr></table>
   <div class="foot">ราคานี้ยังไม่รวมภาษีมูลค่าเพิ่ม · ส่งฟรีในเส้นทางเดินรถประจำ</div>`],
  ["ใบแจ้งหนี้_INV-8812_รุ่งเรืองน้ำมันพืช.pdf", "application/pdf", `<h1>ใบแจ้งหนี้</h1><div class="co">บจก. รุ่งเรืองน้ำมันพืช (ข้อมูลสมมติสำหรับสาธิต)</div>
   <div class="meta"><div>ถึง: บริษัท สมใจค้าส่ง จำกัด</div><div>เลขที่ INV-8812<br>ครบกำหนดชำระ วันที่ 10</div></div>
   <table><tr><th>รายการ</th><th>จำนวน</th><th>ราคา/ลัง</th><th>รวม (บาท)</th></tr>
   <tr><td>น้ำมันพืช 1 ลิตร (ลัง 12 ขวด)</td><td>150 ลัง</td><td class="n">490.00</td><td class="n">73,500.00</td></tr>
   <tr class="tot"><td colspan="3">ยอดที่ต้องชำระ</td><td class="n">73,500.00</td></tr></table>`],
  ["เงินเดือนพนักงาน_ตุลาคม.pdf", "application/pdf", `<h1>เอกสารภายใน — ห้ามเผยแพร่</h1><div class="co">สรุปเงินเดือนพนักงาน (ข้อมูลสมมติ)</div>
   <table><tr><th>พนักงาน</th><th>ตำแหน่ง</th><th>เงินเดือน</th></tr><tr><td>—</td><td>—</td><td class="n">—</td></tr></table>`],
  ["ตารางเช็คสต็อกเช้านี้.png", "image/png", `<h1>เช็คสต็อกหน้าคลัง</h1><div class="co">ตรวจนับโดย ต้น คลังสินค้า</div>
   <table><tr><th>สินค้า</th><th>คงเหลือ</th><th>สถานะ</th></tr>
   <tr><td>น้ำดื่ม 600 มล.</td><td>320 แพ็ค</td><td>ปกติ</td></tr>
   <tr><td>นมกล่อง UHT</td><td>180 ลัง</td><td>ปกติ</td></tr>
   <tr><td>บะหมี่กึ่งสำเร็จรูป</td><td>210 ลัง</td><td>ปกติ</td></tr>
   <tr><td>ปลากระป๋อง</td><td>95 ลัง</td><td>ปกติ</td></tr>
   <tr><td>น้ำมันพืช 1 ลิตร</td><td>40 ลัง</td><td class="warn">ต่ำกว่าจุดสั่งซื้อ</td></tr>
   <tr><td>ผงซักฟอก 900 กรัม</td><td>15 ลัง</td><td class="warn">ใกล้หมด</td></tr></table>`],
];
const missing = docs.filter(([f]) => !fs.existsSync("assets/" + f));
if (missing.length) {
  const b = await chromium.launch({ channel: "chrome" });
  const p = await b.newPage({ viewport: { width: 640, height: 520 }, deviceScaleFactor: 2 });
  for (const [f, mime, html] of missing) {
    await p.setContent(`<style>${DOC_CSS}</style>${html}`);
    if (mime === "application/pdf") await p.pdf({ path: "assets/" + f, format: "A4", printBackground: true });
    else await p.screenshot({ path: "assets/" + f, fullPage: true });
  }
  await b.close();
}
const MIME = Object.fromEntries(docs.map(([f, m]) => [f, m]));
async function upload(who, file) {
  return req("POST", "/api/upload", TOK[who], { file_name: file, mime_type: MIME[file], data_base64: fs.readFileSync("assets/" + file).toString("base64") });
}

// ---------- 4. rooms ----------
const others = (...ks) => ks.map((k) => ID[k]);
const G1 = (await req("POST", "/api/conversations/group", TOK.W, { name: "ทีมขาย-คลัง-จัดส่ง", folder: "work", member_ids: others("S", "N", "T", "P", "M", "K", "B", "A") })).id;
const G2 = (await req("POST", "/api/conversations/group", TOK.W, { name: "บัญชี-การเงิน", folder: "work", member_ids: others("S", "N", "B", "A") })).id;
const direct = async (k) => (await req("POST", "/api/conversations/direct", TOK.W, { friend_id: ID[k] })).id;
const [DS, DN, DA, DO] = [await direct("S"), await direct("N"), await direct("A"), await direct("O")];
for (const [c, folder, pin] of [[G1, "work", true], [G2, "work", true], [DA, "work", true], [DO, "work", true], [DS, "work", false], [DN, "personal", false]])
  await req("PUT", `/api/conversations/${c}/meta`, TOK.W, { folder, is_pinned: pin });

// ---------- 5. story (HH:MM are "minutes before now" anchors, see retime) ----------
const posted = []; // [msgId, minutesAgo, conv]
async function say(conv, who, minsAgo, body) {
  if (typeof body === "string") body = { type: "text", content: body };
  const m = await req("POST", `/api/conversations/${conv}/messages`, TOK[who], body);
  posted.push([m.id, minsAgo, conv]);
  return m;
}
async function file(conv, who, minsAgo, name, caption) {
  const att = await upload(who, name);
  if (caption) await say(conv, who, minsAgo + 0.5, caption);
  return say(conv, who, minsAgo, { type: MIME[name].startsWith("image/") ? "image" : "file", content: name, attachment: att });
}

// G1 — the busy room the owner has not opened all morning (minutes before "now").
const rule = await say(G1, "S", 200, "📌 กติกากลุ่ม: ออเดอร์ที่ต้องส่งภายในวันนี้ แจ้งในกลุ่มก่อน 10 โมงเช้าทุกครั้ง");
await say(G1, "T", 178, "อรุณสวัสดิ์ครับ เช้านี้รับของเข้าคลังแล้ว นมกล่อง UHT 120 ลัง ปลากระป๋อง 80 ลัง ตรวจนับครบตามใบส่งของครับ");
await file(G1, "T", 175, "ตารางเช็คสต็อกเช้านี้.png");
await say(G1, "S", 170, "ขอบคุณครับต้น วันนี้ออเดอร์เยอะ ทุกคนอัปเดตงานในกลุ่มนี้นะครับ");
await say(G1, "P", 163, "ร้านเจ๊หมวยสั่งน้ำดื่ม 600 มล. 100 แพ็ค กับบะหมี่กึ่งสำเร็จรูป 50 ลังค่ะ ทำใบเสนอราคาให้แล้ว");
await file(G1, "P", 162, "ใบเสนอราคา_QT-0014_ร้านเจ๊หมวย.pdf");
await say(G1, "P", 155, "เจ๊หมวยขอส่วนลด 3% ถ้าสั่งครบ 100 แพ็คค่ะ แพรให้เองไม่ได้ ขอคุณวิชัยอนุมัตินะคะ");
await say(G1, "M", 148, "ร้านป้าศรีมินิมาร์ทสั่งน้ำมันพืช 1 ลิตร 60 ลังค่ะ ต้องการภายในสัปดาห์นี้");
await say(G1, "T", 143, "น้ำมันพืชในคลังเหลือ 40 ลังครับ ไม่พอออเดอร์ป้าศรี ขาดอีก 20 ลัง");
await say(G1, "B", 137, "เดี๋ยวบอสโทรถามซัพพลายเออร์ให้ครับ");
await say(G1, "B", 126, "ซัพพลายเออร์ส่งได้พรุ่งนี้บ่ายครับ ถ้าสั่ง 200 ลังได้ราคาลังละ 492 บาท บอสส่งใบขออนุมัติไว้ในห้องบัญชี-การเงินแล้ว");
await say(G1, "M", 119, "งั้นมายด์แจ้งป้าศรีว่าส่ง 40 ลังก่อน ที่เหลือส่งตามหลังเมื่อของเข้านะคะ");
await say(G1, "K", 112, "แจ้งทุกคนครับ รถกระบะคันที่ 2 เข้าศูนย์เปลี่ยนผ้าเบรก วันนี้รอบบ่ายวิ่งได้คันเดียว");
await say(G1, "K", 109, "รอบบ่ายส่งได้แค่สายนนทบุรีกับปากเกร็ด สายบางบัวทองต้องเลื่อนไปพรุ่งนี้เช้าครับ");
await say(G1, "S", 104, "ใครดูแลลูกค้าสายบางบัวทอง ช่วยโทรแจ้งลูกค้าด้วยนะครับ");
await say(G1, "P", 100, "ร้านเจ๊หมวยอยู่สายบางบัวทองค่ะ เดี๋ยวแพรโทรแจ้งเอง");
await say(G1, "N", 93, "แจ้งฝ่ายขายค่ะ ร้านโชคดีพาณิชย์ค้างชำระ 45,600 บาท เกินกำหนดมา 15 วันแล้ว");
await say(G1, "N", 91, "รบกวนตามเก็บเงินก่อนส่งของรอบใหม่นะคะ");
await say(G1, "S", 84, "รับทราบครับ เดี๋ยวผมโทรตามเอง");
await say(G1, "M", 72, "ลูกค้าใหม่ มินิมาร์ทบ้านสวน ขอเปิดเครดิต 30 วัน วงเงิน 50,000 บาทค่ะ");
await say(G1, "N", 69, "ลูกค้าใหม่ต้องให้คุณวิชัยอนุมัติวงเงินก่อนค่ะ ขอสำเนาทะเบียนการค้าด้วยนะคะ");
await say(G1, "T", 56, "ผงซักฟอก 900 กรัม เหลือ 15 ลัง ใกล้หมดแล้วครับ");
await say(G1, "B", 52, "รับทราบครับ รวมไปกับใบสั่งซื้อรอบหน้า");
await say(G1, "K", 38, "รอบเช้าส่งครบ 6 ร้านแล้วครับ ร้านเจริญผลขอให้ส่งหลังบ่ายสองโมงในครั้งต่อไป");
await say(G1, "P", 24, "เจ๊หมวยถามว่าส่วนลด 3% ได้ไหมคะ ลูกค้ารอคำตอบก่อนเที่ยงค่ะ");
await say(G1, "S", 12, { type: "text", content: "ด่วน! ร้านเจริญผลขอเพิ่มนมกล่อง UHT 10 ลัง ส่งพร้อมรอบบ่ายวันนี้ ใครรับได้กดรับงานครับ", priority: "urgent", task_status: "open" });
await req("PUT", `/api/conversations/${G1}/pin-message`, TOK.W, { message_id: rule.id });

// G2 — accounting: approval card + supplier invoice.
await file(G2, "N", 140, "ใบแจ้งหนี้_INV-8812_รุ่งเรืองน้ำมันพืช.pdf", "ใบแจ้งหนี้ค่าน้ำมันพืชล็อตก่อน ครบกำหนดชำระวันที่ 10 ค่ะ");
await say(G2, "N", 130, "ยอดขายเมื่อวานรวม 186,450 บาท เงินสด 72,300 บาท เงินโอน 114,150 บาทค่ะ");
await say(G2, "B", 125, { type: "flex_card", content: "ขออนุมัติสั่งซื้อน้ำมันพืช 200 ลัง", flex_payload: {
  app_code: "expense_claim", app_title: "ขออนุมัติสั่งซื้อ", badge: "ใบสั่งซื้อ PO-0031", icon: "receipt_long", color: "#0288D1",
  title: "น้ำมันพืช 1 ลิตร 200 ลัง", subtitle: "ผู้ขาย บจก. รุ่งเรืองน้ำมันพืช · ส่งพรุ่งนี้บ่าย", highlight: "98,400 บาท", note: "ลังละ 492 บาท · ขอโดย บอส จัดซื้อ", status: "รออนุมัติ"} });

// Direct rooms.
await say(DS, "S", 20, "คุณวิชัยครับ ร้านเจ๊หมวยขอส่วนลด 3% ถ้าสั่งน้ำดื่มครบ 100 แพ็ค ถ้าให้ส่วนลด กำไรต่อแพ็คจะเหลือประมาณ 4 บาท เราจะให้ไหมครับ");
await say(DN, "N", 45, "คุณวิชัยคะ สัปดาห์หน้าต้องจ่ายซัพพลายเออร์รวม 412,000 บาท ยอดเงินในบัญชีพอจ่ายค่ะ ส่งรายละเอียดไว้ในห้องบัญชี-การเงินแล้วนะคะ");
await say(DA, "A", 240, "สวัสดีครับคุณวิชัย ผมคือ BC AI ผู้ช่วยประจำตัว พิมพ์ถามเรื่องงานได้เลย เช่น ร่างข้อความถึงลูกค้า สรุปตัวเลข หรือวางแผนงานครับ");
await say(DO, "O", 3, "📢 ประกาศ: วันเสาร์นี้ปิดคลังตรวจนับสต็อกประจำเดือน 13:00–17:00 น. งดรับ-ส่งสินค้าช่วงเวลาดังกล่าว");

// BC Keep notes for the owner.
await req("POST", "/api/notes", TOK.W, { title: "ลูกค้าสายบางบัวทอง", content: "ร้านเจ๊หมวย · ร้านทองดีมินิมาร์ท · ร้านสองพี่น้อง\nรอบส่งปกติ: อังคาร / ศุกร์ ช่วงเช้า", is_pinned: true });
await req("POST", "/api/notes", TOK.W, { title: "เป้ายอดขายเดือนนี้", content: "เป้ารวม 4.5 ล้านบาท\nเน้นเปิดลูกค้ามินิมาร์ทใหม่ 10 ร้าน", is_pinned: false });

// ---------- 6. back-date to this morning + mark read by the staff (not by the owner) ----------
const now = Date.now();
const iso = (minsAgo) => new Date(now - minsAgo * 60000).toISOString().replace("Z", "+00:00");
const upd = posted.map(([id, mins]) => [id, iso(mins)]);
mongo(`
const upd = ${JSON.stringify(upd)};
for (const [id, at] of upd) db.messages.updateOne({ _id: id }, { $set: { created_at: at } });
// Everything not scripted above (group-created notices, onboarding welcomes made at login) goes
// back to yesterday so the morning story sorts on top.
const scripted = new Set(upd.map(([id]) => id));
const yesterday = ${now} - 86400000;
db.messages.find({ conversation_id: { $ne: ${JSON.stringify(KEEP_ROOM)} } }, { _id: 1 }).toArray().forEach((m, i) => {
  if (!scripted.has(m._id)) db.messages.updateOne({ _id: m._id }, { $set: { created_at: new Date(yesterday + i * 1000).toISOString().replace("Z", "+00:00") } });
});
for (const c of db.conversations.find({ _id: { $ne: ${JSON.stringify(KEEP_ROOM)} } }).toArray()) {
  const last = c.last_message && db.messages.findOne({ _id: c.last_message.id });
  if (!last) continue;
  const staff = c.member_ids.filter((m) => m !== "user_jead" && m !== "user_ai");
  if (c.type === "group") db.messages.updateMany({ conversation_id: c._id }, { $addToSet: { read_by: { $each: staff } } });
  db.conversations.updateOne({ _id: c._id }, { $set: { updated_at: last.created_at, created_at: last.created_at, "last_message.created_at": last.created_at } });
}
print(db.messages.countDocuments({ conversation_id: { $ne: ${JSON.stringify(KEEP_ROOM)} } }));
`);
fs.writeFileSync("rooms.json", JSON.stringify({ G1, G2, DS, DN, DA, DO }, null, 1));
console.log("seeded", posted.length, "messages", { G1, G2, DS, DN, DA, DO });
