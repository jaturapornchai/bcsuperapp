# AGENTS.md — BC Super App (`d:\bcapp`)

## กฎหลักของโปรเจกต์
- สื่อสารภาษาไทยเสมอ เรียก **"ลุงจืด"** เสมอ
- **Stack หลัก**:
  - **Backend**: Rust (`axum`, `tokio`, `mongodb`, `reqwest`, `jsonwebtoken`) ที่พอร์ต `8095` ออกแบบเน้นความเร็วสูงสุด (Compound Indexes + Batch Fetch ป้องกัน N+1)
  - **Database**: MongoDB (`127.0.0.1:27029`, database `bcapp`) เก็บข้อมูลทั้งหมด
  - **Object Storage**: MinIO (`127.0.0.1:9120`, bucket `bcapp-storage`) เก็บรูปภาพและเอกสารแบบถาวร พร้อมรองรับการสั่งทำลายไฟล์จริงทันทีเมื่อส่งผิด (`Hard Purge`)
  - **AI Brain**: DeepSeek API (`deepseek-chat` / `deepseek-reasoner`) เป็นผู้ช่วยอัจฉริยะประจำทุกคนและทุกกลุ่ม (`@ai` ในกลุ่ม, สรุปแชท & แกะงาน, เกลาคำพูดทางการ)
  - **Frontend & Admin Backoffice**: Flutter (`d:\bcapp\frontend`) โค้ดชุดเดียวรองรับครบ 5 แพลตฟอร์ม (`android`, `ios`, `macos`, `windows`, `web`)
- **ความปลอดภัยของข้อมูลลับ**:
  - ห้าม Hardcode หรือ Commit `DEEPSEEK_API_KEY`, รหัสผ่าน, หรือความลับใดๆ ลงใน Git เด็ดขาด (เก็บใน `.env` ที่ถูก ignore เท่านั้น)
