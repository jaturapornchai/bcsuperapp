# UX/UI & API Specification — BC Super App (`d:\bcapp\frontend`)

## 1. โจทย์หลักจากลุงจืด
1. **ออกแบบ UX/UI สวยๆ ดูพรีเมี่ยม (Premium Enterprise Super App)**:
   - วิธีใช้งานแบบแอปแชทที่คนไทยคุ้นเคย แต่ยกระดับความสวยงามให้ดูหรูหรา พรีเมี่ยม ทันสมัย (Glassmorphism, Smooth Micro-interactions, Gradient Badges, Card Shadows นุ่มนวล, Dark/Light Contrast ชัดเจน, ห้องแชทสีฟ้าครามคลาสสิก `#8CABD9` หรือสลับธีมห้องแชทพรีเมี่ยมได้)
   - **กฎเหล็ก UI (Baseline-First)**: ตัวหนังสือ ปุ่ม ช่องกรอก ไอคอน Badge ในแถวเดียวกันต้องอยู่ระนาบ Baseline และกึ่งกลางแนวนอนเดียวกันเป๊ะ (`crossAxisAlignment: CrossAxisAlignment.center`) ห้ามเหลื่อมสูง-ต่ำ
   - ใช้ภาษาไทยที่เข้าใจง่ายทุกจุด ฟอนต์ไทยสวยอ่านง่าย (`GoogleFonts.prompt` หรือ `GoogleFonts.notoSansThai`)
   - รองรับทั้งหน้าจอมือถือ (Mobile Layout) และหน้าจอเว็บ/เดสก์ท็อป (Responsive Split-Pane แบบแอปแชทบนเดสก์ท็อป + แท็บจัดการหลังบ้าน Admin Backoffice)

2. **ฟีเจอร์หลัก + ฟีเจอร์ที่คนโซเชียล (Pantip / โซเชียลไทย) เรียกร้องมากที่สุด**:
   - **เข้าสู่ระบบด้วย Gmail (Google Sign-In / Quick Gmail Switcher)**:
     - มีปุ่ม **"เข้าสู่ระบบด้วยบัญชี Gmail (Google)"** ดีไซน์พรีเมี่ยม พร้อมปุ่ม Quick Switch สลับบัญชีทดสอบ (`jead@bcapp.local` ลุงจืด Super Admin, `somchai.sales@bcapp.local` สมชาย ฝ่ายขาย, `nida.acc@bcapp.local` นิดา บัญชีการเงิน) หรือกรอก Gmail ใดๆ เพื่อสมัคร/ล็อกอินได้ทันที
     - ซิงค์ประวัติแชทและไฟล์ข้ามเครื่องอัตโนมัติ 100% บน MongoDB (แก้ปัญหาย้ายเครื่องแล้วแชทหาย)
   - **แท็บที่ 1: หน้าหลัก (Home — เพื่อน, กลุ่ม, และบริการเสริม Super App)**:
     - โปรไฟล์ของฉันด้านบน (แก้ไขชื่อ, ตั้งค่าสถานะ, ตั้งค่า **BC ID** สำหรับให้คนอื่นค้นหา, แสดง **QR Code ของฉัน** ด้วย `QrImageView` จาก `qr_flutter`)
     - ปุ่ม **เพิ่มเพื่อน** (ค้นหาด้วย BC ID, ค้นหาด้วย Gmail, หรือกรอก/สแกน QR Token) และปุ่ม **สร้างกลุ่มใหม่**
     - แถบ **บริการเสริมด่วน (Mini-Apps Grid)** เปิดระบบเสริมแบบ WebView / In-App Modal ได้ทันที
     - รายชื่อ **บัญชีทางการ (Official Accounts)**, **กลุ่ม (Groups)**, และ **เพื่อน (Friends)** กดเพื่อเริ่มแชทหรือดูโปรไฟล์ได้ทันที
   - **แท็บที่ 2: แชท (Chats — Real-time Chat + แก้ Pain Point โซเชียล)**:
     - **แถบโฟลเดอร์แยกหมวดแชท (แก้ปัญหาเรื่องงานปนเรื่องส่วนตัว)**:
       - แท็บกรองด้านบน: `ทั้งหมด`, `ส่วนตัว`, `เรื่องงาน`, `กลุ่ม`, `ปักหมุด`, `ยังไม่อ่าน`
     - **ช่องค้นหาข้อความและชื่อไฟล์ข้ามห้องแชท** (`GET /api/messages/search?q=...`)
     - **ภายในห้องแชท (Chat Room)**:
       - **แถบปักหมุดประกาศด้านบนหัวห้องแชท (Pin Announcement Banner)**: แสดงข้อความที่ปักหมุดไว้ กดดูหรือเปลี่ยนข้อความปักหมุดได้
       - **Bubble ข้อความ**:
         - ข้อความฝั่งเราสีเขียวพาสเทลพรีเมี่ยม (`#A8F0B8` / `#06C755`), ฝั่งเพื่อนสีขาวพร้อม Avatar และชื่อผู้ส่ง
         - แสดงคำว่า **`อ่านแล้ว`** (หรือ `อ่านแล้ว 2` ในกลุ่ม) และเวลาส่งด้านข้าง Bubble
         - กดค้างหรือคลิกเมนูที่ข้อความเพื่อ: **ตอบกลับ (Reply)**, **ปักหมุดประกาศบนหัวห้อง (Pin)**, **บันทึกเข้า Keep**, หรือ **ยกเลิกข้อความ (Unsend)**
       - **ส่งสติ๊กเกอร์ (Sticker Picker)**, **ส่งรูปภาพและไฟล์เอกสาร (อัปโหลดเข้า MinIO ถาวร)**, และ **ส่งการ์ดจาก Mini-App (Rich Flex Card)**
       - **ปุ่ม "คลังรูป & ไฟล์ถาวร (ไม่หมดอายุ)" บนหัวห้องแชท**:
         - เปิด Drawer/Modal แสดง 3 แท็บ: `รูปภาพ`, `ไฟล์เอกสาร`, `โน้ตกลุ่ม` พร้อมป้ายกำกับ **"เก็บถาวรบน MinIO — ไม่มีวันหมดอายุ"** (แก้ปัญหารูป/ไฟล์ในแชทหมดอายุ)
   - **แท็บที่ 3: บริการเสริม Super App (Mini-Apps Center — Dynamic WebView)**:
     - แสดงรายการระบบเสริมทั้งหมดจาก Backend (`GET /api/mini-apps`) แยกตามหมวดหมู่ (`งานบุคคล/ออฟฟิศ`, `การเงิน/บัญชี`, `บริการลูกค้า`)
     - กดเปิด Mini-App เพื่อใช้งานผ่าน **In-App WebView / Interactive Mini-App Runner** ที่ส่ง SSO Token ของ Gmail ปัจจุบันเข้าไปอัตโนมัติ และสามารถกดส่ง **Rich Flex Card** (เช่น การ์ดอนุมัติใบลา, การ์ดใบเสนอราคา, การ์ดเบิกค่าใช้จ่าย, การ์ดนัดหมาย) เข้าห้องแชทที่เลือกได้ทันที!
   - **แท็บที่ 4: Keep & โปรไฟล์ (Keep Cloud Vault & Settings)**:
     - **BC Keep (บันทึกส่วนตัวบนคลาวด์ไม่จำกัดเวลา)**: จดบันทึก เก็บลิงก์ เก็บไฟล์สำคัญส่วนตัว ซิงค์ตาม Gmail
     - ตั้งค่าโปรไฟล์, BC ID, QR Code, และสลับธีมห้องแชท
   - **แท็บที่ 5: ระบบหลังบ้าน (Admin Backoffice — แสดงสำหรับสิทธิ์ Admin)**:
     - **Dashboard ภาพรวม**: จำนวนผู้ใช้งาน, จำนวนห้องแชท, ข้อความทั้งหมด, จำนวนไฟล์และพื้นที่ใน MinIO (`bcapp-storage`), จำนวน Mini-Apps
     - **จัดการระบบเสริม WebView (Mini-App Manager)**: เพิ่ม/แก้ไข/เปิด-ปิด/เปลี่ยน URL/เปลี่ยนสีและไอคอนของ Mini-App สดๆ โดยไม่ต้องอัปเดตแอป!
     - **ประกาศ Broadcast (Official OA Broadcast)**: ส่งข้อความประกาศเข้าห้อง `BC Official OA` ของผู้ใช้ทุกคนได้ในคลิกเดียว
     - **จัดการผู้ใช้งาน (User Management)**: ดูรายชื่อผู้ใช้ที่สมัครด้วย Gmail และปรับสิทธิ์ Admin/User

---

## 2. Backend API Contract (`http://127.0.0.1:8095`)
- **Base URL**: `http://127.0.0.1:8095`
- **WebSocket URL**: `ws://127.0.0.1:8095/ws?token=<JWT>`
- **Header**: `Authorization: Bearer <JWT>`
- **Endpoints**:
  1. `POST /api/auth/google`
     - Body: `{"email": "...", "display_name": "...", "avatar_url": "...", "google_id": "..."}`
     - Response: `{"token": "...", "user": {"id": "...", "email": "...", "display_name": "...", "bc_id": "...", "avatar_url": "...", "status_message": "...", "qr_token": "...", "role": "admin"}}`
  2. `GET /api/auth/me` -> คืนข้อมูล `user`
  3. `PUT /api/auth/profile` -> Body: `{"display_name": "...", "bc_id": "...", "status_message": "...", "avatar_url": "..."}`
  4. `GET /api/friends` -> คืน `List<User>`
  5. `GET /api/users/search?q=...` -> ค้นหาเพื่อนด้วย BC ID, Gmail, ชื่อ, หรือ QR Token
  6. `POST /api/friends/add` -> Body: `{"target_id": "...", "bc_id": "...", "email": "...", "qr_token": "..."}` -> คืน `{"friend": {...}, "conversation_id": "..."}`
  7. `GET /api/conversations?folder=all` -> คืนรายการห้องแชทพร้อม `unread_count`, `is_pinned`, `folder`, `pinned_message`, `last_message`
  8. `POST /api/conversations/direct` -> Body: `{"friend_id": "..."}`
  9. `POST /api/conversations/group` -> Body: `{"name": "...", "folder": "work"|"personal", "member_ids": [...]}`
  10. `PUT /api/conversations/:id/meta` -> Body: `{"folder": "work"|"personal", "is_pinned": true|false, "name": "..."}`
  11. `PUT /api/conversations/:id/pin-message` -> Body: `{"message_id": "..."}`
  12. `GET /api/conversations/:id/messages` -> คืนรายการข้อความพร้อม `read_count`, `read_by`, `is_unsent`, `attachment`, `flex_payload`, `reply_to`
  13. `POST /api/conversations/:id/messages` -> Body: `{"type": "text"|"sticker"|"image"|"file"|"flex_card", "content": "...", "sticker_code": "...", "attachment": {...}, "flex_payload": {...}, "reply_to_id": "..."}`
  14. `POST /api/conversations/:id/read` -> มาร์คว่าอ่านแล้ว
  15. `DELETE /api/messages/:id/unsend` -> ยกเลิกข้อความ (Unsend)
  16. `GET /api/conversations/:id/vault` -> คืน `{"images": [...], "files": [...], "links": [...]}`
  17. `GET /api/messages/search?q=...` -> ค้นหาข้อความและไฟล์
  18. `GET /api/notes?conversation_id=...`, `POST /api/notes`, `DELETE /api/notes/:id` -> ระบบ Keep และโน้ตกลุ่ม
  19. `POST /api/upload` -> Body JSON: `{"file_name": "...", "mime_type": "...", "data_base64": "..."}` -> คืน `{"key": "...", "url": "http://127.0.0.1:8095/api/files/...", "file_name": "...", "mime_type": "...", "file_size": 123}`
  20. `GET /api/mini-apps` -> คืนรายการ Mini-Apps ที่เปิดใช้งาน
  21. `GET /api/admin/overview` -> สถิติหลังบ้าน
  22. `GET /api/admin/users`, `PUT /api/admin/users/:id/role`
  23. `GET /api/admin/mini-apps`, `POST /api/admin/mini-apps`, `PUT /api/admin/mini-apps/:id`, `DELETE /api/admin/mini-apps/:id`
  24. `POST /api/admin/broadcast` -> Body: `{"title": "...", "content": "..."}`
