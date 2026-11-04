// E2E: 5 test accounts chat together, create a group with BC AI as secretary,
// send image + document, then verify MongoDB (docker exec mongosh) and MinIO
// objects directly. Run: node e2e_chat5.mjs  (backend on :8095, docker up)
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const BASE = process.env.API_URL || 'http://127.0.0.1:8095';
const TEST_ROOM = 'conv_group_test5'; // backend/src/seed.rs TEST_CHAT_ROOM_ID
const AI_FALLBACK_PREFIX = '🤖 **BC AI (DeepSeek Assistant)** ขอตอบคำถามเรื่อง'; // ai_routes.rs offline reply
// Same names as the seed: login updates display_name, so sending anything else would rename them.
const TESTERS = [
  ['tester1@bcapp.local', 'ก้อง (ทดสอบ 1)'],
  ['tester2@bcapp.local', 'แพร (ทดสอบ 2)'],
  ['tester3@bcapp.local', 'บอส (ทดสอบ 3)'],
  ['tester4@bcapp.local', 'มายด์ (ทดสอบ 4)'],
  ['tester5@bcapp.local', 'ต้น (ทดสอบ 5)'],
];

let passed = 0;
const ok = (msg) => console.log(`✅ [${++passed}] ${msg}`);
function assert(cond, msg) {
  if (!cond) throw new Error(`❌ ${msg}`);
}
async function req(method, path, token, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token && { Authorization: `Bearer ${token}` }) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch {}
  return { status: res.status, ok: res.ok, json, text };
}
const sha = (buf) => createHash('sha256').update(buf).digest('hex');
// Values interpolated here are server-generated ids/keys (uuid/timestamp), never user text.
const mongo = (js) =>
  JSON.parse(execFileSync('docker', ['exec', 'bcapp-mongodb', 'mongosh', '--quiet', 'bcapp', '--eval', `EJSON.stringify(${js})`]).toString());
function minioHas(key) {
  try {
    execFileSync('docker', ['exec', 'bcapp-minio', 'ls', `/data/bcapp-storage/${key}`], { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}
function openWs(token) {
  const events = [];
  const ws = new WebSocket(`${BASE.replace(/^http/, 'ws')}/ws?token=${token}`);
  ws.onmessage = (e) => { try { events.push(JSON.parse(e.data)); } catch {} };
  const ready = new Promise((r, j) => { ws.onopen = r; ws.onerror = () => j(new Error('ws rejected')); });
  return { ws, events, ready };
}
async function waitFor(fn, ms = 4000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (fn()) return true;
    await new Promise((r) => setTimeout(r, 100));
  }
  return false;
}
async function send(token, convId, body) {
  const r = await req('POST', `/api/conversations/${convId}/messages`, token, body);
  assert(r.ok && r.json?.id, `send failed: ${r.text}`);
  return r.json;
}
async function aiReplyAfter(token, convId, msgId) {
  const list = await req('GET', `/api/conversations/${convId}/messages`, token);
  const idx = list.json.findIndex((m) => m.id === msgId);
  return list.json.slice(idx + 1).find((m) => m.sender_id === 'user_ai');
}
async function upload(token, convId, fileName, mime, bytes) {
  const r = await req('POST', '/api/upload', token, {
    file_name: fileName, mime_type: mime, data_base64: bytes.toString('base64'), conversation_id: convId,
  });
  assert(r.ok && r.json?.key, `upload ${fileName} failed: ${r.text}`);
  return r.json;
}

async function main() {
  console.log('🚀 E2E ทดสอบแชท 5 คน + กลุ่ม + AI เลขา + รูป/เอกสาร + ตรวจฐานข้อมูล\n');
  const health = await req('GET', '/api/health');
  assert(health.json?.status === 'ok', `health: ${health.text}`);

  // 1. Login all five testers
  const users = [];
  for (const [email, name] of TESTERS) {
    const r = await req('POST', '/api/auth/google', null, { email, display_name: name });
    assert(r.ok && r.json?.token, `login ${email}: ${r.text}`);
    assert(r.json.user.role === 'user', `${email} must stay role user, got ${r.json.user.role}`);
    users.push({ ...r.json.user, token: r.json.token });
  }
  ok(`ผู้ทดสอบ 5 คนเข้าสู่ระบบ: ${users.map((u) => u.display_name).join(', ')}`);

  // 2. Everyone sees the seeded room with all 5 + BC AI
  for (const u of users) {
    const list = await req('GET', '/api/conversations', u.token);
    const room = list.json.find((c) => c.id === TEST_ROOM);
    assert(room, `${u.email} cannot see ${TEST_ROOM}`);
    const ids = room.members.map((m) => m.id);
    assert(ids.includes('user_ai') && users.every((x) => ids.includes(x.id)), `room members wrong: ${ids}`);
  }
  ok('ทั้ง 5 คนเห็น "ห้องทดสอบแชท 5 คน" และมี BC AI เป็นสมาชิก');

  // 3. Realtime: each tester talks, the other four receive it over WebSocket
  const sockets = users.map((u) => openWs(u.token));
  await Promise.all(sockets.map((s) => s.ready));
  const roundMsgs = [];
  for (const [i, u] of users.entries()) {
    const m = await send(u.token, TEST_ROOM, { type: 'text', content: `สวัสดีครับ/ค่ะ ผม/ฉัน ${u.display_name} ทดสอบรอบ ${Date.now()}` });
    roundMsgs.push(m);
    for (const [j, s] of sockets.entries()) {
      if (j === i) continue;
      const got = await waitFor(() => s.events.some((e) => e.event === 'new_message' && e.message?.id === m.id));
      assert(got, `${users[j].email} did not receive realtime message from ${u.email}`);
    }
  }
  ok('คุยกันเองครบ 5 คน — ทุกข้อความเด้งถึงอีก 4 คนแบบเรียลไทม์ (WebSocket)');

  // 4. Read receipts: everyone opens the room
  for (const u of users) assert((await req('POST', `/api/conversations/${TEST_ROOM}/read`, u.token)).ok, 'mark read');
  const afterRead = await req('GET', `/api/conversations/${TEST_ROOM}/messages`, users[0].token);
  const first = afterRead.json.find((m) => m.id === roundMsgs[0].id);
  assert(first.read_count >= 4, `read_count expected >= 4, got ${first.read_count}`);
  ok(`สถานะอ่านแล้ว: ข้อความแรกมีคนอ่าน ${first.read_count} คน`);

  // 5. BC AI secretary in the seeded room
  const askRoom = await send(users[0].token, TEST_ROOM, { type: 'text', content: '@ai เลขาช่วยสรุปสั้นๆ ว่าเมื่อกี้ใครทักทายบ้าง' });
  const aiRoom = await aiReplyAfter(users[0].token, TEST_ROOM, askRoom.id);
  assert(aiRoom?.content, 'BC AI did not reply in test room');
  const realAi = !aiRoom.content.startsWith(AI_FALLBACK_PREFIX);
  ok(`AI เลขาตอบในห้องทดสอบ (${realAi ? 'DeepSeek ตอบจริง' : 'ข้อความสำรอง: ยังไม่ได้ตั้งคีย์ DeepSeek'}): "${aiRoom.content.slice(0, 80).replace(/\n/g, ' ')}…"`);

  // 6. Tester2 creates a new group with everyone + BC AI
  const groupName = `ประชุมทีมทดสอบ E2E ${new Date().toISOString().slice(0, 16)}`;
  const g = await req('POST', '/api/conversations/group', users[1].token, {
    name: groupName, folder: 'work', member_ids: [...users.filter((u) => u !== users[1]).map((u) => u.id), 'user_ai'],
  });
  assert(g.ok && g.json?.id, `create group: ${g.text}`);
  const gid = g.json.id;
  for (const u of users) {
    const list = await req('GET', '/api/conversations', u.token);
    assert(list.json.some((c) => c.id === gid), `${u.email} cannot see new group`);
  }
  ok(`${users[1].display_name} สร้างกลุ่ม "${groupName}" — สมาชิกทุกคนเห็นกลุ่ม`);

  // 7. Meeting chat + AI secretary takes minutes
  await send(users[1].token, gid, { type: 'text', content: 'วาระวันนี้: ปิดยอดขายเดือนตุลาคม และนัดลูกค้า VIP วันศุกร์ 10 โมง' });
  await send(users[2].token, gid, { type: 'text', content: 'ผมรับทำใบเสนอราคาลูกค้า VIP ส่งภายในพฤหัสนี้' });
  await send(users[3].token, gid, { type: 'text', content: 'ฉันจะสรุปยอดขายตุลาคมส่งในกลุ่มพรุ่งนี้' });
  const askMinutes = await send(users[4].token, gid, { type: 'text', content: '@ai เลขาช่วยจดรายงานการประชุม ใครรับงานอะไร กำหนดส่งเมื่อไร' });
  const minutes = await aiReplyAfter(users[4].token, gid, askMinutes.id);
  assert(minutes?.content, 'BC AI did not take minutes in new group');
  const sum = await req('POST', '/api/ai/summarize', users[1].token, { conversation_id: gid });
  assert(sum.ok && sum.json?.summary, `summarize: ${sum.text}`);
  ok(`AI เลขาจดรายงานการประชุมในกลุ่มใหม่ + สรุปแชทได้ (${minutes.content.length} ตัวอักษร)`);

  // 8. Image + document: upload, send, download byte-for-byte
  const png = readFileSync(new URL('./docs/screenshots/02_chat_room_screen.png', import.meta.url));
  const pdf = Buffer.from(
    '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n' +
    '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 100]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n'
  );
  const img = await upload(users[2].token, gid, 'chat_screen.png', 'image/png', png);
  const doc = await upload(users[3].token, gid, 'quotation_vip.pdf', 'application/pdf', pdf);
  const imgMsg = await send(users[2].token, gid, { type: 'image', content: 'chat_screen.png', attachment: img });
  const docMsg = await send(users[3].token, gid, { type: 'file', content: 'quotation_vip.pdf', attachment: doc });
  for (const [att, src] of [[img, png], [doc, pdf]]) {
    const dl = await fetch(`${BASE}/api/files/${att.key}`);
    const bytes = Buffer.from(await dl.arrayBuffer());
    assert(dl.ok && sha(bytes) === sha(src), `download mismatch ${att.file_name}`);
    assert(dl.headers.get('content-type')?.startsWith(att.mime_type), `content-type ${dl.headers.get('content-type')}`);
  }
  const vault = await req('GET', `/api/conversations/${gid}/vault`, users[0].token);
  const vaultKeys = JSON.stringify(vault.json);
  assert(vaultKeys.includes(img.key) && vaultKeys.includes(doc.key), `vault missing files: ${vault.text.slice(0, 200)}`);
  ok(`ส่งรูป (${png.length} ไบต์) + เอกสาร PDF — ดาวน์โหลดกลับมาตรงทุกไบต์ (sha256) และขึ้นในคลังไฟล์ของกลุ่ม`);

  // 9. MongoDB direct check
  const dbConv = mongo(`db.conversations.findOne({_id:'${gid}'},{member_ids:1,name:1,conv_type:1})`);
  assert(dbConv && dbConv.member_ids.length === 6 && dbConv.member_ids.includes('user_ai'), `db conv: ${JSON.stringify(dbConv)}`);
  const dbMsgs = mongo(`db.messages.find({conversation_id:'${gid}'},{sender_id:1,msg_type:1,type:1,attachment:1}).toArray()`);
  const kinds = dbMsgs.map((m) => m.msg_type ?? m.type);
  assert(dbMsgs.length >= 7 && dbMsgs.some((m) => m.sender_id === 'user_ai'), `db messages: ${dbMsgs.length}`);
  assert(kinds.includes('image') && kinds.includes('file'), `db kinds: ${kinds}`);
  const dbFiles = mongo(`db.files.find({key:{$in:['${img.key}','${doc.key}']}},{key:1,conversation_id:1,file_size:1,uploader_id:1}).toArray()`);
  assert(dbFiles.length === 2 && dbFiles.every((f) => f.conversation_id === gid), `db files: ${JSON.stringify(dbFiles)}`);
  ok(`MongoDB: conversations สมาชิก 6 (รวม AI), messages ${dbMsgs.length} รายการ (${[...new Set(kinds)].join('/')}), files 2 รายการผูกกับกลุ่ม`);

  // 10. MinIO direct check
  assert(minioHas(img.key) && minioHas(doc.key), 'objects missing in MinIO bucket');
  ok('MinIO: พบไฟล์รูปและเอกสารจริงใน bucket bcapp-storage');

  // 11. Wrong-room confidential file → hard purge removes Mongo + MinIO
  const secret = await upload(users[4].token, gid, 'secret_wrong_room.pdf', 'application/pdf', pdf);
  const secretMsg = await send(users[4].token, gid, { type: 'file', content: 'ส่งผิดห้อง', is_confidential: true, attachment: secret });
  assert(minioHas(secret.key), 'secret not stored before purge');
  assert((await req('DELETE', `/api/messages/${secretMsg.id}/unsend?hard=true`, users[4].token)).ok, 'purge failed');
  assert((await fetch(`${BASE}/api/files/${secret.key}`)).status === 404, 'purged file still downloadable');
  assert(!minioHas(secret.key), 'purged object still in MinIO');
  assert(mongo(`db.files.countDocuments({key:'${secret.key}'})`) === 0, 'purged file doc still in Mongo');
  assert(mongo(`db.messages.countDocuments({_id:'${secretMsg.id}'})`) === 0, 'purged message still in Mongo');
  ok('ส่งไฟล์ความลับผิดห้อง → ลบถาวรได้: ไม่เหลือใน MongoDB และ MinIO');

  // 12. Privacy: a non-member can't read, post, join, or eavesdrop over WebSocket
  const outsider = await req('POST', '/api/auth/google', null, { email: 'somchai.sales@bcapp.local', display_name: 'สมชาย ฝ่ายขาย' });
  const ot = outsider.json.token;
  const peek = await req('GET', `/api/conversations/${gid}/messages`, ot);
  const sneak = await req('POST', `/api/conversations/${gid}/messages`, ot, { type: 'text', content: 'แอบส่ง' });
  assert(peek.status === 403 && sneak.status === 403, `outsider read=${peek.status} post=${sneak.status}`);
  assert(mongo(`db.conversations.findOne({_id:'${gid}'}).member_ids.length`) === 6, 'outsider post joined the room');
  const spy = openWs(ot);
  await spy.ready;
  const probe = await send(users[0].token, gid, { type: 'text', content: 'ข้อความเฉพาะสมาชิก' });
  await waitFor(() => sockets[1].events.some((e) => e.message?.id === probe.id));
  await new Promise((r) => setTimeout(r, 500));
  assert(!spy.events.some((e) => e.conversation_id === gid), 'outsider websocket received group events');
  spy.ws.close();
  const anon = openWs('');
  const anonRejected = await anon.ready.then(() => false, () => true);
  assert(anonRejected, 'websocket without token was accepted');
  ok(`คนนอกกลุ่ม: อ่าน/ส่งไม่ได้ (HTTP ${peek.status}), ไม่ถูกดึงเข้ากลุ่ม, ไม่ได้รับข้อความทาง WebSocket; ไม่มี token ต่อ WebSocket ไม่ได้`);

  sockets.forEach((s) => s.ws.close());
  console.log(`\n🎉 ผ่านทั้งหมด ${passed} ขั้นตอน`);
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
