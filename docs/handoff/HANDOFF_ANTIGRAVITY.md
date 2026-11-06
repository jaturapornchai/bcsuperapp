# HANDOFF — สำหรับ Antigravity (BC Super App `d:\bcapp`)

## 1. สถานะล่าสุด
- Repo: `https://github.com/jaturapornchai/bcsuperapp` branch `main` = commit `6f10f2b` (push แล้ว, working tree สะอาด)
- อ่านก่อนเริ่ม: [AGENTS.md](../../AGENTS.md), [README.md](../../README.md), [docs/push-fcm.md](../push-fcm.md)
- Stack: Rust backend (`axum`) `:8095` + WebSocket `/ws`, MongoDB `:27029` (db `bcapp`), MinIO `:9120` (bucket `bcapp-storage`), DeepSeek AI, Flutter frontend (Android/iOS/macOS/Windows/Web)

## 2. งานที่ทำเสร็จแล้ว (ต่อจาก handoff UX/UI เดิม)
| commit | งาน |
|---|---|
| `06d9dd1` | บัญชีทดสอบ 5 คน `tester1-5@bcapp.local` + ห้อง `conv_group_test5` (มี BC AI) + ปุ่ม Windows เปิด 5 หน้าต่าง login อัตโนมัติ; admin เลือกธีมสี 7 แบบตามกิจการ |
| `6263b2f` | อ่าน/ส่ง/รับ WebSocket ของห้องได้เฉพาะสมาชิก; WS ไม่มี token = 401 |
| `e098cca` | `/api/admin/*` ต้องเป็น admin (เช็ก role ใน MongoDB); สมัครใหม่ได้ role `user` |
| `4bc08f0` | ป๊อปอัปแจ้งเตือนข้อความใหม่ (Windows/Android/เว็บ) แตะเปิดห้อง, ข้อความลับซ่อนเนื้อหา |
| `cd38bd6` | เสียงเตือน 8 แบบ เลือกแยก ทั่วไป/ด่วน/BC AI |
| `6f10f2b` | Push ตอนปิดแอปผ่าน FCM (Android + เว็บ); แก้ WS ไม่ต่อใหม่หลังหลุด + backend ตัด socket เมื่อรับไม่ทัน |

## 3. จุดสำคัญในโค้ด
- สิทธิ์สมาชิกห้อง: `require_member` — [chat_routes.rs:31](../../backend/src/routes/chat_routes.rs#L31)
- สิทธิ์ admin: extractor `AdminUser` — [auth.rs:117](../../backend/src/auth.rs#L117)
- ธีม: route `/api/settings/theme` — [lib.rs:166](../../backend/src/lib.rs#L166)
- ปุ่มเปิด 5 หน้าต่างทดสอบ (`--test-login` / `--test-slot`): [login_screen.dart:799](../../frontend/lib/screens/login_screen.dart#L799)
- WebSocket backend: เครื่องออนไลน์ `device_online` [ws.rs:39](../../backend/src/ws.rs#L39), ping `PING_EVERY` 20 วินาที [ws.rs:95](../../backend/src/ws.rs#L95)
- WebSocket frontend: ต่อใหม่อัตโนมัติ `_retryWebSocket` (2→30 วินาที) [api_service.dart:198](../../frontend/lib/services/api_service.dart#L198), รหัสเครื่อง `deviceId` [api_service.dart:98](../../frontend/lib/services/api_service.dart#L98)
- Push backend: `Fcm` [push.rs:62](../../backend/src/push.rs#L62), `notify_new_message` [push.rs:271](../../backend/src/push.rs#L271) (เรียกหลัง broadcast `new_message` ใน chat/ai/admin routes); API [push_routes.rs](../../backend/src/routes/push_routes.rs) `POST /api/devices`, `DELETE /api/devices/:id`, `GET /api/push/config`
- Push frontend: [push_service.dart](../../frontend/lib/services/push_service.dart) (`start` บรรทัด 29, `syncSettings` บรรทัด 41), channel เสียง `createPushChannels` [notification_service.dart:135](../../frontend/lib/services/notification_service.dart#L135), Android [MainActivity.kt](../../frontend/android/app/src/main/kotlin/com/bcapp/frontend/MainActivity.kt) (MethodChannel `bcapp/push`), เว็บ `window.bcPushGetToken` ใน [web/index.html](../../frontend/web/index.html) + [web/push_sw.js](../../frontend/web/push_sw.js)
- เสียงเตือน: `frontend/assets/sounds/*.wav` + สำเนา Android `frontend/android/app/src/main/res/raw/alert_*.wav` สร้างด้วย `node tool/make_alert_sounds.mjs` (รหัสเสียงต้องตรงกับ `SOUND_CODES` ใน `push.rs` — `flutter test` ตรวจให้)

## 4. วิธีรันและทดสอบ
```bash
docker compose up -d                      # MongoDB + MinIO
cd backend && cargo run                   # :8095 (log "push off: ..." = ยังไม่ตั้ง Firebase ซึ่งปกติ)
cd backend && cargo test                  # ต้องมี MongoDB + MinIO + openssl
cd frontend && flutter analyze && flutter test
node e2e_test.mjs
node e2e_chat5.mjs                        # แชท 5 คน + AI + รูป/PDF + ตรวจ DB/MinIO + คนนอกห้องถูกกัน
```
- Windows: `cargo build`/`cargo test` ล้มถ้า `bcapp-backend.exe` รันอยู่ (ไฟล์ถูกล็อก) → หยุด backend ก่อน
- `frontend/lib/services/api_service.dart` เป็นไฟล์ CRLF — ระวังเวลาแก้ด้วย script

## 5. งานค้าง / ยังไม่ได้ verify
1. **ส่ง push จริงกับ Google ยังไม่ได้ทดสอบ** — รอลุงจืดสร้าง Firebase ตาม [docs/push-fcm.md](../push-fcm.md) §Config แล้วทดสอบบนมือถือ Android จริง + เว็บ (ปัดแอปทิ้ง → ส่งจากอีกบัญชี → เด้งพร้อมเสียง → แตะแล้วเปิดห้อง)
2. แตะ push แล้วเปิดห้อง และแตะ toast บน Windows แล้วเปิดห้อง — ยังไม่ได้ทดสอบด้วยการคลิกจริง
3. iOS/macOS push (APNs + บัญชี Apple Developer) ยังไม่ทำ; Windows ไม่มี FCM (เตือนได้เฉพาะตอนแอปเปิด)
4. ข้อจำกัดที่รู้แล้ว (ทำต่อเมื่อลุงจืดสั่ง): token ที่เปลี่ยนตอนแอปปิดจะส่งใหม่ตอนเปิดแอปครั้งถัดไป (ไม่มี `onNewToken`); เว็บที่มีแท็บแอปเปิดอยู่ แตะแจ้งเตือนจะแค่สลับแท็บ ไม่เปิดห้อง; backend ไม่ส่งซ้ำเมื่อ FCM ตอบ 429/5xx
5. ห้อง `conv_group_test5` มีข้อความทดสอบค้างจากการทดสอบอัตโนมัติ (ไม่กระทบการทำงาน)

## 6. กฎที่ห้ามพลาด
1. **ความลับ**: ห้าม commit `.env`, `google-services.json`, `backend/secrets/`, `*firebase-adminsdk*.json`, API key (`sk-...`, `AIza...`), VAPID key — ทั้งหมดถูก ignore ไว้แล้ว; ค่า Firebase เว็บส่งจาก backend `/api/push/config` (อ่านจาก `.env`) ไม่ฝังในโค้ด; อีเมลในโค้ด/เทสต์ใช้ `@bcapp.local` หรือ `@example.com` เท่านั้น
2. **ห้ามอ้างเครื่องหมายการค้าคนอื่น** (เช่น LINE, Lark) ใน UI หรือโค้ด
3. ข้อความบนหน้าจอเป็นภาษาไทยที่เข้าใจง่าย; ตัวหนังสือ/ปุ่ม/ไอคอน/Badge ในแถวเดียวกันต้องอยู่กึ่งกลางระนาบเดียวกัน
4. **ห้ามเพิ่มแพ็กเกจ Dart `firebase_core` / `firebase_messaging`** — บน Windows จะดาวน์โหลด Firebase C++ SDK ~627MB และ build โต 8GB+; push ใช้ native Kotlin + Firebase JS SDK แทน (เหตุผลเต็มใน docs/push-fcm.md §Dependency)
5. Git: ห้าม force-push `main`, ห้าม `git pull`/`reset --hard origin` เอง, push เมื่อลุงจืดสั่งเท่านั้น; สแกน `git diff --cached` หาความลับก่อน commit
6. เจอบั๊กระหว่างทาง → แก้ที่ root cause พร้อมเทสต์ที่พังก่อนแก้ แล้วรายงาน; ห้ามบอกว่าเสร็จก่อนรันเทสต์ในข้อ 4 ผ่าน

## 7. Prompt สำเร็จรูปสำหรับสั่ง Antigravity
```text
อ่าน d:\bcapp\AGENTS.md, d:\bcapp\README.md และ d:\bcapp\docs\handoff\HANDOFF_ANTIGRAVITY.md ให้ครบก่อนเริ่ม
สถานะล่าสุดคือ commit 6f10f2b บน main

งานที่ต้องทำ: <ลุงจืดใส่งานที่ต้องการ>

ข้อกำหนด:
- ทำตามกฎในหัวข้อ 6 ของ HANDOFF_ANTIGRAVITY.md ทุกข้อ (ห้าม commit ความลับ, ห้ามอ้าง LINE/Lark, UI ภาษาไทย, ห้ามเพิ่ม firebase_core/firebase_messaging)
- อ้างอิงโค้ดจริง (ไฟล์:บรรทัด) ทุกครั้งที่อธิบาย ไม่แน่ใจให้ถามลุงจืดก่อน
- แก้เสร็จแล้วรันให้ผ่านทั้งหมด:
  cd d:\bcapp\backend && cargo test
  cd d:\bcapp\frontend && flutter analyze && flutter test
  cd d:\bcapp && node e2e_test.mjs && node e2e_chat5.mjs
- รายงานเป็นภาษาไทย: แก้อะไร ไฟล์ไหน ผลเทสต์ และสิ่งที่ยังไม่ได้ verify
- ห้าม push ขึ้น GitHub จนกว่าลุงจืดจะสั่ง
```
