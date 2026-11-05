# แจ้งเตือนตอนปิดแอป (Push ผ่าน Firebase Cloud Messaging)

## Objective
เมื่อมีข้อความใหม่ขณะที่แอปปิดอยู่ (Android ปิดแอป/ปัดทิ้ง, เว็บปิดแท็บ) เครื่องยังเด้งแจ้งเตือน ใช้เสียงที่ผู้ใช้เลือกไว้ และแตะแล้วเปิดห้องนั้น

## Workflow
1. แอปเปิด → `PushService.start()` ([push_service.dart](../frontend/lib/services/push_service.dart)) ขอ token จาก FCM
   - Android: ผ่าน `MainActivity.kt` (MethodChannel `bcapp/push`)
   - เว็บ: ผ่าน `window.bcPushGetToken` ใน `web/index.html` + `web/push_sw.js`
2. ส่ง token + ค่าตั้ง "เสียงและการแจ้งเตือน" ของเครื่องไปที่ `POST /api/devices` (เก็บใน MongoDB `device_tokens`) — เปลี่ยนค่าตั้งเมื่อไรก็ส่งใหม่อัตโนมัติ
3. แอปต่อ WebSocket พร้อม `device=<รหัสเครื่อง>` → backend รู้ว่าเครื่องนี้ออนไลน์อยู่ และไม่ส่ง push ซ้ำกับป๊อปอัปในแอป
4. มีข้อความใหม่ → backend ([push.rs](../backend/src/push.rs)) หาเครื่องของสมาชิกห้อง (ไม่รวมคนส่ง) ที่เปิดป๊อปอัปไว้และ **ไม่ได้ต่อ WebSocket** แล้วส่งผ่าน FCM HTTP v1
   - Android ใช้ช่องแจ้งเตือน `push_<รหัสเสียง>` ที่แอปสร้างไว้ (เสียงจาก `res/raw/alert_<รหัสเสียง>.wav`)
   - ข้อความด่วน/BC AI ได้เสียงตามที่เลือก; ปิดเสียงหรือผู้ส่งส่งแบบเงียบ → `push_none`
5. แตะแจ้งเตือน → แอปเปิดห้องนั้น (Android ส่ง `conversation_id` เข้า MainActivity, เว็บเปิด `/?conversation=<id>`)
6. FCM ตอบว่า token ใช้ไม่ได้แล้ว (`UNREGISTERED`) → backend ลบเครื่องนั้นทิ้ง; ออกจากระบบ → แอปเรียก `DELETE /api/devices/<id>`

## Config — สร้าง Firebase (ลุงจืดทำเองครั้งเดียว)
1. เข้า [Firebase console](https://console.firebase.google.com) → **Add project** (ตั้งชื่อเช่น `bc-super-app`)
2. **Android**: Project settings → General → Your apps → เพิ่มแอป Android ชื่อแพ็กเกจ `com.bcapp.frontend` → ดาวน์โหลด `google-services.json` → วางที่ `frontend/android/app/google-services.json`
3. **เว็บ**: Your apps → เพิ่มแอป Web → คัดลอกค่า `apiKey`, `appId`, `messagingSenderId`
4. **คีย์เว็บพุช**: Settings → General → แท็บ **Cloud Messaging** → Web configuration → Web Push certificates → **Generate Key Pair** → คัดลอกคีย์สาธารณะ
5. **คีย์ฝั่งเซิร์ฟเวอร์**: Settings → แท็บ **Service accounts** → **Generate New Private Key** → บันทึกเป็น `backend/secrets/fcm-service-account.json`
6. ใส่ใน `.env` ที่โฟลเดอร์ราก (ไฟล์นี้ไม่เข้า git):
   ```
   FCM_SERVICE_ACCOUNT_FILE=secrets/fcm-service-account.json
   FCM_WEB_API_KEY=<apiKey>
   FCM_WEB_APP_ID=<appId>
   FCM_WEB_SENDER_ID=<messagingSenderId>
   FCM_WEB_VAPID_KEY=<คีย์จากข้อ 4>
   ```
   path ของ `FCM_SERVICE_ACCOUNT_FILE` นับจากโฟลเดอร์ `backend/` (ที่ backend รันอยู่)
7. รีสตาร์ท backend → log ต้องขึ้น `push on: FCM project <ชื่อโปรเจกต์>`; build APK ใหม่ (ต้องมี `google-services.json` ตอน build)

ไฟล์ `google-services.json`, `secrets/`, `*firebase-adminsdk*.json` ถูก ignore ใน `.gitignore` แล้ว — **ห้าม commit**

## Dependency
- Backend: ใช้ของที่มีอยู่แล้ว (`reqwest`, `jsonwebtoken` RS256 แลก OAuth token จาก service account แล้วเก็บไว้ใช้ ~55 นาที)
- Android: `com.google.firebase:firebase-messaging` ผ่าน Firebase BoM `35.1.0` + Gradle plugin `com.google.gms.google-services` `4.5.0` (ใช้เฉพาะเมื่อมี `google-services.json`)
- เว็บ: Firebase JS SDK `13.2.0` โหลดจาก `www.gstatic.com` เฉพาะตอนเปิด push แล้วเท่านั้น
- ไม่ได้ใช้แพ็กเกจ Dart `firebase_core`/`firebase_messaging` เพราะบน Windows จะดาวน์โหลด Firebase C++ SDK (~627MB) และทำให้โฟลเดอร์ build โต 8GB+ ([flutterfire#12175](https://github.com/firebase/flutterfire/issues/12175), [flutterfire#16967](https://github.com/firebase/flutterfire/issues/16967))

## Usage Example
```bash
# ตรวจว่า backend เปิด push แล้ว (ต้องล็อกอินก่อน; web = null ถ้ายังไม่ใส่ FCM_WEB_*)
curl -H "Authorization: Bearer <JWT>" http://127.0.0.1:8095/api/push/config
# -> {"enabled":true,"web":{"apiKey":"...","appId":"...","messagingSenderId":"...","projectId":"...","vapidKey":"..."}}

# ทดสอบทั้งเส้นทางกับ FCM จำลอง (ไม่ต้องมี Firebase จริง; ต้องมี MongoDB + openssl)
cd backend
cargo test --test push_integration
```
ทดสอบกับเครื่องจริง: ติดตั้ง APK → ล็อกอิน `tester2@bcapp.local` → ปัดแอปทิ้ง → ส่งข้อความจากอีกบัญชีเข้า "ห้องทดสอบแชท 5 คน" → มือถือเด้งพร้อมเสียงที่เลือก → แตะแล้วเปิดห้อง

## Limitation
- Windows ไม่มี FCM: ยังเตือนได้เฉพาะตอนแอปเปิดอยู่ (รวมย่อหน้าต่าง)
- iOS/macOS ต้องใช้ APNs + บัญชี Apple Developer ยังไม่ได้ทำ
- ปิด "แสดงป๊อปอัป" = ไม่ส่ง push ให้เครื่องนั้น (Android เล่นเสียงโดยไม่โชว์แจ้งเตือนไม่ได้)
- เว็บ: เสียงเป็นเสียงของเบราว์เซอร์/ระบบ (เลือกเสียงเองไม่ได้ ทำได้แค่เงียบ); ต้องเปิดผ่าน `https` หรือ `localhost`/`127.0.0.1`; ถ้ามีแท็บแอปเปิดอยู่แล้ว แตะแจ้งเตือนจะแค่สลับไปแท็บนั้น ไม่เปิดห้องให้
- Firebase ประกาศว่า `getToken()` บนเว็บเป็น API เก่า (deprecated) แต่ยังใช้ได้ และ HTTP v1 ยังส่งด้วย `token`; เปลี่ยนเป็น `register()` เมื่อฝั่งส่งรองรับ
- token ที่เปลี่ยนตอนแอปปิดอยู่ จะถูกส่งใหม่ตอนเปิดแอปครั้งถัดไป
- ข้อความตัวอย่างใน push (ชื่อคนส่ง + ข้อความ 120 ตัวอักษร) วิ่งผ่านเซิร์ฟเวอร์ Google; ข้อความลับส่งแค่ "ส่งข้อความลับ 🔒"
- backend ไม่ลองส่งซ้ำเมื่อ FCM ตอบ 429/5xx (จะ log ไว้)
