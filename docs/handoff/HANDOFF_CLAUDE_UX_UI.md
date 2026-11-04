# HANDOFF DOCUMENT — สำหรับ Claude Code (ยกระดับ UX/UI ระดับพรีเมี่ยม — BC Super App)

## 1. ภาพรวมโปรเจกต์ (`d:\bcapp`)
- **Repository**: `https://github.com/jaturapornchai/bcsuperapp`
- **Backend (`d:\bcapp\backend`)**: Rust (`axum`, `tokio`, `mongodb`, `reqwest`, `jsonwebtoken`) รันที่ `http://127.0.0.1:8095` (WebSocket: `ws://127.0.0.1:8095/ws?token=<JWT>`)
- **Database & Storage ([docker-compose.yml](file:///d:/bcapp/docker-compose.yml))**:
  - MongoDB 7.0: `127.0.0.1:27029` (database `bcapp`)
  - MinIO S3: `127.0.0.1:9120` (bucket `bcapp-storage` เก็บรูปภาพและเอกสารแบบถาวร พร้อมรองรับการลบทำลายไฟล์ทันทีเมื่อส่งผิด)
- **AI Brain**: DeepSeek API (`deepseek-chat` / `deepseek-reasoner`) ตั้งค่าผ่าน `.env` (`DEEPSEEK_API_KEY`) หรือผ่านหน้า Admin Backoffice
- **Frontend (`d:\bcapp\frontend`)**: Flutter Cross-Platform รองรับครบ 5 แพลตฟอร์ม (`android`, `ios`, `macos`, `windows`, `web`)

---

## 2. โครงสร้างไฟล์ Frontend ที่ Claude ต้องปรับปรุง UX/UI (`d:\bcapp\frontend\lib`)
1. [`lib/main.dart`](file:///d:/bcapp/frontend/lib/main.dart) — Entrypoint, Auth Gate, และการสลับหน้าจอระหว่าง `LoginScreen` กับ `MainShell`
2. [`lib/theme/app_theme.dart`](file:///d:/bcapp/frontend/lib/theme/app_theme.dart) — Design System หลัก (สี LINE Emerald `#06C755`, Executive Slate `#0F172A`, ฟอนต์ไทย `GoogleFonts.promptTextTheme`, คอมโพเนนต์ `UserAvatar`, `PillBadge`, และธีมพื้นหลังห้องแชท 3 โหมด)
3. [`lib/models/models.dart`](file:///d:/bcapp/frontend/lib/models/models.dart) — Data Models ทั้งหมด (`AppUser`, `Conversation`, `ChatMessage`, `AttachmentInfo`, `VaultData`, `MiniAppItem`, `NoteItem`, `AdminOverview`, `AiSummaryResult`, `AiAssistResult`, `AiAdminSettings`)
4. [`lib/services/api_service.dart`](file:///d:/bcapp/frontend/lib/services/api_service.dart) — ตัวเชื่อมต่อ REST API และ WebSocket Real-time ทั้ง 27 Endpoints
5. [`lib/screens/login_screen.dart`](file:///d:/bcapp/frontend/lib/screens/login_screen.dart) — หน้าเข้าสู่ระบบด้วยบัญชี Gmail และปุ่มสลับบัญชีทดสอบด่วน (`jead@bcapp.local`, `somchai.sales@bcapp.local`, `nida.acc@bcapp.local`)
6. [`lib/screens/main_shell.dart`](file:///d:/bcapp/frontend/lib/screens/main_shell.dart) — โครงหน้าจอหลัก (Responsive: Desktop Split-View `>= 900px` และ Mobile Bottom Navigation `< 900px`) ประกอบด้วย 5 แท็บ:
   - แท็บ 0: **หน้าหลัก (Home)** — โปรไฟล์องค์กร, ตั้งค่า BC ID, QR Code (`QrImageView`), เพิ่มเพื่อน, สร้างกลุ่ม, บริการเสริมด่วน, บัญชีทางการ, กลุ่ม, และเพื่อน
   - แท็บ 1: **แชท (Chats)** — แถบแยกโฟลเดอร์ (`ทั้งหมด`, `ส่วนตัว`, `เรื่องงาน`, `กลุ่ม`, `ปักหมุด`, `ยังไม่อ่าน`), ค้นหาข้อความ/ไฟล์ข้ามห้องแชท, และรายการห้องแชทพร้อม Badge ข้อความยังไม่อ่าน
   - แท็บ 2: **บริการเสริม (Mini-Apps Center)** — ศูนย์รวมระบบเสริม WebView แยกหมวดหมู่
   - แท็บ 3: **BC Keep** — คลังบันทึกส่วนตัวถาวรซิงค์ตามบัญชี Gmail
   - แท็บ 4: **หลังบ้าน (Admin Backoffice)** — สถิติระบบ, ตั้งค่าสมองกล DeepSeek AI, จัดการ Mini-App WebView สดโดยไม่ต้องอัปเดตแอป, โอนย้ายห้องแชทเมื่อพนักงานลาออก (`1-Click Handover + AI Briefing`), และส่งประกาศ Broadcast
7. [`lib/screens/chat_room_screen.dart`](file:///d:/bcapp/frontend/lib/screens/chat_room_screen.dart) — หน้าห้องแชทสไตล์ LINE ครบวงจร:
   - แถบปักหมุดประกาศบนหัวห้องแชท (Pin Announcement Banner)
   - ลายน้ำนิรภัยองค์กร (Enterprise Security Watermark)
   - ฟองข้อความแสดงสถานะ **`อ่านแล้ว`** (และ `อ่านแล้ว N` ในกลุ่ม)
   - ปุ่ม **`🙋‍♂️ กดรับงานนี้`** -> **`✅ รับงานโดย...`** -> **`🎉 เสร็จสิ้น`** บนฟองข้อความ
   - สวิตช์โหมดความเร่งด่วน (`ปกติ` / `🚨 ด่วนพิเศษ DING` / `🌙 ส่งเงียบนอกเวลา`)
   - สวิตช์ **`🔒 โหมดความลับ`** และปุ่มด่วน **`ส่งผิดลบได้`** (ลบข้อความไร้ร่องรอยและทำลายไฟล์ใน MinIO จริง)
   - การ์ด **LINE Flex Card** พร้อมปุ่ม **`✅ อนุมัติทันที`** / **`❌ ไม่อนุมัติ`** ในห้องแชท
   - ปุ่ม **`✨ AI สรุปแชท & แกะงาน`**, **`@ai ถามสมองกลในกลุ่ม`**, และ **`🪄 AI เกลาคำพูด / แนะนำคำตอบ`**
   - Drawer **"คลังรูป & ไฟล์ถาวร (MinIO Vault)"** แยกแท็บรูปภาพ, ไฟล์เอกสาร, และโน้ตกลุ่ม
8. [`lib/screens/mini_app_runner_screen.dart`](file:///d:/bcapp/frontend/lib/screens/mini_app_runner_screen.dart) — หน้าต่างรันระบบเสริม Mini-App WebView พร้อม SSO Token และส่งการ์ด Flex Card เข้าห้องแชท

---

## 3. กฎเหล็ก UX/UI ที่ต้องยึดถือ
1. **Baseline-First 100%**: ตัวหนังสือ ปุ่ม ช่องกรอก ไอคอน และ Badge ในแถวเดียวกันต้องอยู่ระนาบ Baseline และกึ่งกลางแนวนอนเดียวกันเป๊ะ (`crossAxisAlignment: CrossAxisAlignment.center`) ห้ามเหลื่อมสูง-ต่ำ
2. **ภาษาไทยเข้าใจง่าย**: ข้อความทุกจุดใช้ภาษาไทยที่เข้าใจง่ายสำหรับผู้ใช้งานคนไทย
3. **ห้ามแตะความลับ (Iron Rule #21)**: ห้ามใส่ API Key จริง (`sk-...`) หรืออีเมล `@gmail.com` จริงลงในโค้ดหรือคอมมิตขึ้น Git เด็ดขาด (ใช้อีเมลทดสอบ `@bcapp.local` หรือ `@example.com` เท่านั้น)

---

## 4. Prompt สำเร็จรูปสำหรับสั่ง Claude Code
คัดลอก Prompt ด้านล่างนี้ไปวางสั่ง Claude Code ในโฟลเดอร์ `d:\bcapp` ได้ทันที:

```text
อ่านไฟล์ d:\bcapp\AGENTS.md และ d:\bcapp\docs\handoff\HANDOFF_CLAUDE_UX_UI.md จากนั้นช่วยยกระดับ UX/UI ของแอป Flutter ใน d:\bcapp\frontend\lib ให้มีความสวยงาม หรูหรา ดูพรีเมี่ยมระดับโลก (สไตล์ LINE + Lark Enterprise Super App) ทั้งบนหน้าจอมือถือ (Mobile Portrait 412x915) และหน้าจอคอมพิวเตอร์/เว็บ (Desktop Split-View 1440x900) โดย:

1. ปรับปรุงความประณีตของ Visual Hierarchy, ระยะห่าง (Spacing & Padding), เงาการ์ดแบบนุ่มนวล (Soft Layered Shadows), เอฟเฟกต์ Glassmorphism, Micro-animations เวลาเปลี่ยนแท็บหรือเปิดห้องแชท และความคมชัดของ Typography ภาษาไทย
2. ยึดกฎเหล็ก Baseline-First: ตัวหนังสือ ปุ่ม ช่องกรอก ไอคอน และ Badge ในแถวเดียวกันต้องอยู่กึ่งกลางระนาบเดียวกันเป๊ะ ห้ามเหลื่อมสูง-ต่ำ และห้ามเกิด RenderFlex overflow บนทุกขนาดหน้าจอ
3. รักษาฟีเจอร์และการเชื่อมต่อกับ Rust Backend (พอร์ต 8095) ให้ครบ 100%:
   - ล็อกอินด้วย Gmail + สลับบัญชีด่วน
   - แชทสไตล์ LINE + สถานะ "อ่านแล้ว" + แยกโฟลเดอร์งาน/ส่วนตัว + ปักหมุดประกาศ
   - โหมดความลับองค์กร (Confidential + ลายน้ำนิรภัย) + ส่งผิดลบได้ทันทีพร้อมทำลายไฟล์ใน MinIO
   - ปุ่ม "กดรับงานนี้" บนข้อความ + โหมดด่วนพิเศษ (DING) / ส่งเงียบ + กดอนุมัติการ์ด Flex Card ในแชท
   - สมองกล DeepSeek AI (@ai ในกลุ่ม, สรุปแชท & แกะงาน, เกลาคำพูด)
   - ระบบหลังบ้าน Admin Backoffice + โอนย้ายห้องแชทเมื่อพนักงานลาออก (1-Click Handover)
4. เมื่อแก้ไขเสร็จแล้ว ให้รัน 검증:
   - cd d:\bcapp\frontend && flutter analyze && flutter test && flutter build web --release
   - cd d:\bcapp && node e2e_test.mjs
   ตรวจให้ผ่าน 100% ทุกขั้นตอนโดยไม่มีข้อผิดพลาด
```
