use bson::doc;
use chrono::Utc;
use std::collections::HashMap;
use uuid::Uuid;

use crate::{
    models::{
        AttachmentInfo, ConversationDoc, FileDoc, FriendshipDoc, LastMessageSummary, MessageDoc,
        MiniAppDoc, NoteDoc, PinnedMessageSummary, UserDoc,
    },
    AppState,
};

pub async fn ensure_mongo_indexes(db: &mongodb::Database) {
    use mongodb::IndexModel;
    let _ = db
        .collection::<UserDoc>("users")
        .create_indexes(vec![
            IndexModel::builder().keys(doc! { "email": 1 }).build(),
            IndexModel::builder().keys(doc! { "bc_id": 1 }).build(),
            IndexModel::builder().keys(doc! { "qr_token": 1 }).build(),
        ])
        .await;
    let _ = db
        .collection::<ConversationDoc>("conversations")
        .create_indexes(vec![
            IndexModel::builder()
                .keys(doc! { "member_ids": 1, "is_pinned": -1, "updated_at": -1 })
                .build(),
        ])
        .await;
    let _ = db
        .collection::<MessageDoc>("messages")
        .create_indexes(vec![
            IndexModel::builder()
                .keys(doc! { "conversation_id": 1, "created_at": 1 })
                .build(),
            IndexModel::builder()
                .keys(doc! { "conversation_id": 1, "is_unsent": 1, "sender_id": 1 })
                .build(),
            IndexModel::builder()
                .keys(doc! { "conversation_id": 1, "is_confidential": 1 })
                .build(),
        ])
        .await;
    let _ = db
        .collection::<bson::Document>("device_tokens")
        .create_index(IndexModel::builder().keys(doc! { "user_id": 1 }).build())
        .await;
    let _ = db
        .collection::<FriendshipDoc>("friendships")
        .create_index(
            IndexModel::builder()
                .keys(doc! { "user_id": 1, "friend_id": 1 })
                .build(),
        )
        .await;
    let _ = db
        .collection::<NoteDoc>("notes")
        .create_index(
            IndexModel::builder()
                .keys(doc! { "user_id": 1, "conversation_id": 1, "is_pinned": -1 })
                .build(),
        )
        .await;
}

pub async fn seed_initial_data(state: &AppState) -> Result<(), String> {
    // 0. Ensure MongoDB Compound Indexes for high performance
    ensure_mongo_indexes(&state.db).await;

    // 1. Ensure MinIO bucket exists
    if let Err(e) = state.minio.ensure_bucket().await {
        tracing::warn!("MinIO bucket ensure warning: {}", e);
    }

    let now = Utc::now().to_rfc3339();
    let users_coll = state.db.collection::<UserDoc>("users");

    let initial_users = vec![
        UserDoc {
            id: "user_jead".to_string(),
            email: "jead@bcapp.local".to_string(),
            display_name: "ลุงจืด (Super Admin)".to_string(),
            bc_id: "jead.bc".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=Jead+Admin&background=06C755&color=fff&bold=true".to_string(),
            status_message: "ผู้บริหาร BC Super App (Enterprise Security)".to_string(),
            qr_token: "BCQR_JEAD_ADMIN".to_string(),
            role: "admin".to_string(),
            department: "บริหาร".to_string(),
            job_title: "ผู้บริหารสูงสุด (CEO)".to_string(),
            google_id: None,
            created_at: now.clone(),
        },
        UserDoc {
            id: "user_somchai".to_string(),
            email: "somchai.sales@bcapp.local".to_string(),
            display_name: "สมชาย ฝ่ายขาย".to_string(),
            bc_id: "somchai.s".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=Somchai+Sales&background=0288D1&color=fff&bold=true".to_string(),
            status_message: "ติดต่อสั่งซื้อทักแชทได้เลยครับ".to_string(),
            qr_token: "BCQR_SOMCHAI_SALES".to_string(),
            role: "user".to_string(),
            department: "ฝ่ายขาย".to_string(),
            job_title: "ผู้จัดการฝ่ายขาย".to_string(),
            google_id: None,
            created_at: now.clone(),
        },
        UserDoc {
            id: "user_nida".to_string(),
            email: "nida.acc@bcapp.local".to_string(),
            display_name: "นิดา บัญชีการเงิน".to_string(),
            bc_id: "nida.acc".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=Nida+Acc&background=F57C00&color=fff&bold=true".to_string(),
            status_message: "ส่งเอกสารใบกำกับภาษีในแชทนี้ ไฟล์ไม่หมดอายุ".to_string(),
            qr_token: "BCQR_NIDA_ACC".to_string(),
            role: "user".to_string(),
            department: "บัญชีและการเงิน".to_string(),
            job_title: "หัวหน้าฝ่ายบัญชี".to_string(),
            google_id: None,
            created_at: now.clone(),
        },
        UserDoc {
            id: "user_official".to_string(),
            email: "official.bc@bcapp.local".to_string(),
            display_name: "BC Official OA".to_string(),
            bc_id: "@bcofficial".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=BC+OA&background=00B900&color=fff&bold=true".to_string(),
            status_message: "แจ้งข่าวสารและบริการเสริม Super App".to_string(),
            qr_token: "BCQR_OFFICIAL_OA".to_string(),
            role: "admin".to_string(),
            department: "IT & Security".to_string(),
            job_title: "ระบบสื่อสารองค์กร".to_string(),
            google_id: None,
            created_at: now.clone(),
        },
        UserDoc {
            id: "user_ai".to_string(),
            email: "ai@bcapp.local".to_string(),
            display_name: "🤖 BC AI (DeepSeek Assistant)".to_string(),
            bc_id: "@bc.ai".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=BC+AI&background=4F46E5&color=fff&bold=true".to_string(),
            status_message: "สมองกล DeepSeek ผู้ช่วยทุกคนและทุกกลุ่ม (เรียก @ai ได้ทุกห้อง)".to_string(),
            qr_token: "BCQR_DEEPSEEK_AI".to_string(),
            role: "admin".to_string(),
            department: "AI Brain".to_string(),
            job_title: "สมองกลผู้ช่วยประจำทุกคนและทุกกลุ่ม".to_string(),
            google_id: None,
            created_at: now.clone(),
        },
    ];

    for u in &initial_users {
        let existing = users_coll
            .find_one(doc! { "_id": &u.id })
            .await
            .map_err(|e| e.to_string())?;
        if existing.is_none() {
            users_coll
                .insert_one(u)
                .await
                .map_err(|e| e.to_string())?;
        } else {
            let _ = users_coll
                .update_one(
                    doc! { "_id": &u.id },
                    doc! {
                        "$set": {
                            "department": &u.department,
                            "job_title": &u.job_title,
                        }
                    },
                )
                .await;
        }
    }

    // 2. Seed sample permanent files into MinIO + files collection
    let files_coll = state.db.collection::<FileDoc>("files");
    let sample_img_key = "seed_tax_invoice_preview.svg";
    let sample_img_url = format!("{}/api/files/{}", state.config.public_base_url, sample_img_key);
    let svg_bytes = r##"<svg xmlns="http://www.w3.org/2000/svg" width="600" height="360" viewBox="0 0 600 360">
  <rect width="600" height="360" rx="16" fill="#F4FBF7"/>
  <rect x="20" y="20" width="560" height="70" rx="12" fill="#06C755"/>
  <text x="45" y="63" fill="#FFFFFF" font-family="sans-serif" font-size="24" font-weight="bold">BC SUPER APP - ใบกำกับภาษี / ใบเสร็จรับเงิน</text>
  <text x="45" y="130" fill="#1E293B" font-family="sans-serif" font-size="18">เลขที่เอกสาร: INV-2026-08914 (จัดเก็บถาวรบน MinIO)</text>
  <text x="45" y="168" fill="#334155" font-family="sans-serif" font-size="16">ลูกค้า: บริษัท บีซี ซุปเปอร์แอพ จำกัด (สำนักงานใหญ่)</text>
  <text x="45" y="206" fill="#334155" font-family="sans-serif" font-size="16">รายการ: ระบบแชทองค์กร + Mini-App WebView Cloud Sync</text>
  <rect x="45" y="240" width="510" height="75" rx="10" fill="#E2F8EB"/>
  <text x="65" y="285" fill="#047857" font-family="sans-serif" font-size="22" font-weight="bold">ยอดสุทธิ (รวม VAT 7%): 48,150.00 บาท</text>
</svg>"##
        .as_bytes();

    if files_coll
        .find_one(doc! { "_id": "file_seed_invoice_img" })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let _ = state
            .minio
            .put_object(sample_img_key, svg_bytes, "image/svg+xml")
            .await;
        let fdoc = FileDoc {
            id: "file_seed_invoice_img".to_string(),
            key: sample_img_key.to_string(),
            url: sample_img_url.clone(),
            file_name: "ใบกำกับภาษี_INV2026_08914.svg".to_string(),
            mime_type: "image/svg+xml".to_string(),
            file_size: svg_bytes.len() as u64,
            uploader_id: "user_nida".to_string(),
            uploader_name: "นิดา บัญชีการเงิน".to_string(),
            conversation_id: Some("conv_group_office".to_string()),
            created_at: now.clone(),
        };
        let _ = files_coll.insert_one(fdoc).await;
    }

    let sample_doc_key = "seed_quotation_QT2026_0089.txt";
    let sample_doc_url = format!("{}/api/files/{}", state.config.public_base_url, sample_doc_key);
    let doc_bytes = "เอกสารใบเสนอราคาเลขที่ QT-2026-0089\nลูกค้า: บริษัท สยามเทรดดิ้ง จำกัด\nรายการ: ชุดซอฟต์แวร์ BC Super App Enterprise\nยอดรวมสุทธิ: 48,150.00 บาท\nหมายเหตุ: เอกสารนี้จัดเก็บถาวรใน MinIO Object Storage ไม่มีวันหมดอายุ\n".as_bytes();

    if files_coll
        .find_one(doc! { "_id": "file_seed_quotation_doc" })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let _ = state
            .minio
            .put_object(sample_doc_key, doc_bytes, "text/plain; charset=utf-8")
            .await;
        let fdoc = FileDoc {
            id: "file_seed_quotation_doc".to_string(),
            key: sample_doc_key.to_string(),
            url: sample_doc_url.clone(),
            file_name: "ใบเสนอราคา_QT2026_0089.txt".to_string(),
            mime_type: "text/plain".to_string(),
            file_size: doc_bytes.len() as u64,
            uploader_id: "user_somchai".to_string(),
            uploader_name: "สมชาย ฝ่ายขาย".to_string(),
            conversation_id: Some("conv_group_office".to_string()),
            created_at: now.clone(),
        };
        let _ = files_coll.insert_one(fdoc).await;
    }

    // 3. Seed Mini-Apps
    let mini_coll = state.db.collection::<MiniAppDoc>("mini_apps");
    let base_url = &state.config.public_base_url;
    let initial_mini_apps = vec![
        MiniAppDoc {
            id: "mini_ai_copilot".to_string(),
            app_code: "ai_copilot".to_string(),
            title: "สมองกล DeepSeek AI ผู้ช่วยองค์กร".to_string(),
            subtitle: "สรุปแชท ร่างใบเสนอราคา เกลาข้อความทางการ แกะงานกลุ่ม".to_string(),
            category: "ai".to_string(),
            icon_name: "auto_awesome".to_string(),
            color_hex: "#4F46E5".to_string(),
            entry_url: format!("{}/miniapp/ai", base_url),
            is_active: true,
            sort_order: 0,
            created_at: now.clone(),
            updated_at: now.clone(),
        },
        MiniAppDoc {
            id: "mini_leave".to_string(),
            app_code: "leave_approval".to_string(),
            title: "อนุมัติใบลา / งานบุคคล".to_string(),
            subtitle: "ส่งใบลาและส่งการ์ดอนุมัติเข้าแชท".to_string(),
            category: "work".to_string(),
            icon_name: "assignment_turned_in".to_string(),
            color_hex: "#06C755".to_string(),
            entry_url: format!("{}/miniapp/leave", base_url),
            is_active: true,
            sort_order: 1,
            created_at: now.clone(),
            updated_at: now.clone(),
        },
        MiniAppDoc {
            id: "mini_quotation".to_string(),
            app_code: "quick_quotation".to_string(),
            title: "ออกใบเสนอราคาด่วน".to_string(),
            subtitle: "สร้างใบเสนอราคาและแชร์การ์ดให้ลูกค้าในแชท".to_string(),
            category: "work".to_string(),
            icon_name: "receipt_long".to_string(),
            color_hex: "#00B900".to_string(),
            entry_url: format!("{}/miniapp/quotation", base_url),
            is_active: true,
            sort_order: 2,
            created_at: now.clone(),
            updated_at: now.clone(),
        },
        MiniAppDoc {
            id: "mini_expense".to_string(),
            app_code: "expense_claim".to_string(),
            title: "เบิกค่าใช้จ่าย / แนบบิล".to_string(),
            subtitle: "ถ่ายรูปบิลเก็บถาวรใน MinIO ไม่หมดอายุ".to_string(),
            category: "finance".to_string(),
            icon_name: "account_balance_wallet".to_string(),
            color_hex: "#0288D1".to_string(),
            entry_url: format!("{}/miniapp/expense", base_url),
            is_active: true,
            sort_order: 3,
            created_at: now.clone(),
            updated_at: now.clone(),
        },
        MiniAppDoc {
            id: "mini_booking".to_string(),
            app_code: "crm_queue".to_string(),
            title: "จองคิว / นัดหมายลูกค้า".to_string(),
            subtitle: "ระบบนัดหมายผ่าน WebView อัปเดตสดไม่ต้องแก้แอป".to_string(),
            category: "service".to_string(),
            icon_name: "calendar_month".to_string(),
            color_hex: "#7B1FA2".to_string(),
            entry_url: format!("{}/miniapp/booking", base_url),
            is_active: true,
            sort_order: 4,
            created_at: now.clone(),
            updated_at: now.clone(),
        },
    ];

    for app in initial_mini_apps {
        let existing = mini_coll
            .find_one(doc! { "app_code": &app.app_code })
            .await
            .map_err(|e| e.to_string())?;
        if existing.is_none() {
            mini_coll
                .insert_one(app)
                .await
                .map_err(|e| e.to_string())?;
        }
    }

    // 4. Ensure initial group conversation ("กลุ่มประสานงาน BC Office") exists
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let msg_coll = state.db.collection::<MessageDoc>("messages");

    if conv_coll
        .find_one(doc! { "_id": "conv_group_office" })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let pinned_msg = PinnedMessageSummary {
            id: "msg_group_welcome_1".to_string(),
            sender_id: "user_jead".to_string(),
            sender_name: "ลุงจืด (Super Admin)".to_string(),
            msg_type: "text".to_string(),
            content: "📌 ประกาศสำคัญ: รูปภาพและเอกสารในกลุ่มเก็บถาวรบน MinIO และรองรับโหมดความลับองค์กร (ส่งผิดสามารถกดยกเลิก/ลบทำลายไฟล์ออกจากเซิร์ฟเวอร์ได้ทันที)".to_string(),
            created_at: now.clone(),
        };

        let last_msg = LastMessageSummary {
            id: "msg_group_welcome_3".to_string(),
            sender_id: "user_somchai".to_string(),
            sender_name: "สมชาย ฝ่ายขาย".to_string(),
            msg_type: "file".to_string(),
            content: "แนบไฟล์: ใบเสนอราคา_QT2026_0089.txt (ดูได้ที่คลังไฟล์ หรือลิงก์ https://bcapp.local/docs/qt0089)".to_string(),
            created_at: now.clone(),
            read_count: 3,
        };

        let group_conv = ConversationDoc {
            id: "conv_group_office".to_string(),
            conv_type: "group".to_string(),
            name: "กลุ่มประสานงาน BC Office".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=BC+Office&background=06C755&color=fff&bold=true".to_string(),
            folder: "work".to_string(),
            is_pinned: true,
            member_ids: vec![
                "user_jead".to_string(),
                "user_somchai".to_string(),
                "user_nida".to_string(),
                "user_official".to_string(),
                "user_ai".to_string(),
            ],
            user_meta: HashMap::new(),
            pinned_message: Some(pinned_msg),
            last_message: Some(last_msg),
            created_at: now.clone(),
            updated_at: now.clone(),
        };
        conv_coll
            .insert_one(group_conv)
            .await
            .map_err(|e| e.to_string())?;

        let group_messages = vec![
            MessageDoc {
                id: "msg_group_welcome_1".to_string(),
                conversation_id: "conv_group_office".to_string(),
                sender_id: "user_jead".to_string(),
                sender_name: "ลุงจืด (Super Admin)".to_string(),
                sender_avatar: "https://ui-avatars.com/api/?name=Jead+Admin&background=06C755&color=fff&bold=true".to_string(),
                msg_type: "text".to_string(),
                content: "📌 ประกาศสำคัญ: รูปภาพและเอกสารในกลุ่มเก็บถาวรบน MinIO และรองรับโหมดความลับองค์กร (ส่งผิดสามารถกดยกเลิก/ลบทำลายไฟล์ออกจากเซิร์ฟเวอร์ได้ทันที)".to_string(),
                sticker_code: None,
                attachment: None,
                flex_payload: None,
                reply_to: None,
                read_by: vec![
                    "user_jead".to_string(),
                    "user_somchai".to_string(),
                    "user_nida".to_string(),
                    "user_official".to_string(),
                ],
                is_unsent: false,
                is_confidential: false,
                confidential_pin: None,
                expire_at: None,
                priority: "normal".to_string(),
                task_status: None,
                accepted_by: None,
                accepted_at: None,
                created_at: now.clone(),
            },
            MessageDoc {
                id: "msg_group_welcome_2".to_string(),
                conversation_id: "conv_group_office".to_string(),
                sender_id: "user_nida".to_string(),
                sender_name: "นิดา บัญชีการเงิน".to_string(),
                sender_avatar: "https://ui-avatars.com/api/?name=Nida+Acc&background=F57C00&color=fff&bold=true".to_string(),
                msg_type: "image".to_string(),
                content: "ส่งรูปใบกำกับภาษี INV-2026-08914 เก็บเข้าคลังถาวรเรียบร้อยค่ะ".to_string(),
                sticker_code: None,
                attachment: Some(AttachmentInfo {
                    key: sample_img_key.to_string(),
                    url: sample_img_url,
                    file_name: "ใบกำกับภาษี_INV2026_08914.svg".to_string(),
                    mime_type: "image/svg+xml".to_string(),
                    file_size: svg_bytes.len() as u64,
                }),
                flex_payload: None,
                reply_to: None,
                read_by: vec![
                    "user_jead".to_string(),
                    "user_somchai".to_string(),
                    "user_nida".to_string(),
                ],
                is_unsent: false,
                is_confidential: true,
                confidential_pin: None,
                expire_at: None,
                priority: "normal".to_string(),
                task_status: None,
                accepted_by: None,
                accepted_at: None,
                created_at: now.clone(),
            },
            MessageDoc {
                id: "msg_group_welcome_3".to_string(),
                conversation_id: "conv_group_office".to_string(),
                sender_id: "user_somchai".to_string(),
                sender_name: "สมชาย ฝ่ายขาย".to_string(),
                sender_avatar: "https://ui-avatars.com/api/?name=Somchai+Sales&background=0288D1&color=fff&bold=true".to_string(),
                msg_type: "file".to_string(),
                content: "แนบไฟล์: ใบเสนอราคา_QT2026_0089.txt (ดูได้ที่คลังไฟล์ หรือลิงก์ https://bcapp.local/docs/qt0089)".to_string(),
                sticker_code: None,
                attachment: Some(AttachmentInfo {
                    key: sample_doc_key.to_string(),
                    url: sample_doc_url,
                    file_name: "ใบเสนอราคา_QT2026_0089.txt".to_string(),
                    mime_type: "text/plain".to_string(),
                    file_size: doc_bytes.len() as u64,
                }),
                flex_payload: None,
                reply_to: None,
                read_by: vec![
                    "user_jead".to_string(),
                    "user_somchai".to_string(),
                    "user_nida".to_string(),
                ],
                is_unsent: false,
                is_confidential: false,
                confidential_pin: None,
                expire_at: None,
                priority: "normal".to_string(),
                task_status: None,
                accepted_by: None,
                accepted_at: None,
                created_at: now.clone(),
            },
        ];

        msg_coll
            .insert_many(group_messages)
            .await
            .map_err(|e| e.to_string())?;
    } else {
        let _ = conv_coll
            .update_one(
                doc! { "_id": "conv_group_office" },
                doc! { "$addToSet": { "member_ids": "user_ai" } },
            )
            .await;
    }

    // Ensure urgent task message & approval flex card exist in conv_group_office
    if msg_coll
        .find_one(doc! { "_id": "msg_group_urgent_task" })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let urgent_msg = MessageDoc {
            id: "msg_group_urgent_task".to_string(),
            conversation_id: "conv_group_office".to_string(),
            sender_id: "user_jead".to_string(),
            sender_name: "ลุงจืด (Super Admin)".to_string(),
            sender_avatar: "https://ui-avatars.com/api/?name=Jead+Admin&background=06C755&color=fff&bold=true".to_string(),
            msg_type: "text".to_string(),
            content: "🚨 งานด่วน: รบกวนฝ่ายขายและบัญชีตรวจสอบใบเสนอราคา QT-2026-0089 และยืนยันการจัดส่งให้ลูกค้าภายในวันนี้ครับ".to_string(),
            sticker_code: None,
            attachment: None,
            flex_payload: None,
            reply_to: None,
            read_by: vec![
                "user_jead".to_string(),
                "user_somchai".to_string(),
                "user_nida".to_string(),
            ],
            is_unsent: false,
            is_confidential: false,
            confidential_pin: None,
            expire_at: None,
            priority: "urgent".to_string(),
            task_status: Some("accepted".to_string()),
            accepted_by: Some("สมชาย ฝ่ายขาย".to_string()),
            accepted_at: Some(now.clone()),
            created_at: now.clone(),
        };
        let _ = msg_coll.insert_one(urgent_msg).await;
    }

    if msg_coll
        .find_one(doc! { "_id": "msg_group_flex_card" })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let flex_msg = MessageDoc {
            id: "msg_group_flex_card".to_string(),
            conversation_id: "conv_group_office".to_string(),
            sender_id: "user_somchai".to_string(),
            sender_name: "สมชาย ฝ่ายขาย".to_string(),
            sender_avatar: "https://ui-avatars.com/api/?name=Somchai+Sales&background=0288D1&color=fff&bold=true".to_string(),
            msg_type: "flex_card".to_string(),
            content: "[ออกใบเสนอราคาด่วน] บจก. สยามซัพพลาย เทรดดิ้ง — 48,150.00 บาท".to_string(),
            sticker_code: None,
            attachment: None,
            flex_payload: Some(serde_json::json!({
                "app_code": "quick_quotation",
                "title": "ขออนุมัติใบเสนอราคาด่วน #QT-2026-0089",
                "color_hex": "#00B900",
                "heading": "ลูกค้า: บจก. สยามซัพพลาย เทรดดิ้ง",
                "subtitle": "ชุดระบบ BC Super App Enterprise (รายปี)",
                "highlight_value": "48,150.00 บาท",
                "status": "รออนุมัติ",
                "status_label": "รออนุมัติ"
            })),
            reply_to: None,
            read_by: vec![
                "user_jead".to_string(),
                "user_somchai".to_string(),
            ],
            is_unsent: false,
            is_confidential: false,
            confidential_pin: None,
            expire_at: None,
            priority: "normal".to_string(),
            task_status: None,
            accepted_by: None,
            accepted_at: None,
            created_at: now.clone(),
        };
        let _ = msg_coll.insert_one(flex_msg).await;
    }

    // 5. Onboard default admin user ("user_jead") so all 1-1 chats & notes exist
    if let Some(jead_user) = users_coll
        .find_one(doc! { "_id": "user_jead" })
        .await
        .map_err(|e| e.to_string())?
    {
        ensure_user_onboarding(state, &jead_user).await?;
    }

    // 6. Five test accounts sharing one group room, so a chat can be tried end to end
    ensure_test_chat_room(state).await?;

    Ok(())
}

pub const TEST_CHAT_ROOM_ID: &str = "conv_group_test5";

/// Test accounts the login screen offers for trying a 5-person chat.
pub const TEST_ACCOUNTS: [(&str, &str, &str); 5] = [
    ("user_tester1", "tester1@bcapp.local", "ก้อง (ทดสอบ 1)"),
    ("user_tester2", "tester2@bcapp.local", "แพร (ทดสอบ 2)"),
    ("user_tester3", "tester3@bcapp.local", "บอส (ทดสอบ 3)"),
    ("user_tester4", "tester4@bcapp.local", "มายด์ (ทดสอบ 4)"),
    ("user_tester5", "tester5@bcapp.local", "ต้น (ทดสอบ 5)"),
];

async fn ensure_test_chat_room(state: &AppState) -> Result<(), String> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let now = Utc::now().to_rfc3339();

    for (i, (id, email, name)) in TEST_ACCOUNTS.iter().enumerate() {
        let exists = users_coll
            .find_one(doc! { "_id": *id })
            .await
            .map_err(|e| e.to_string())?
            .is_some();
        if !exists {
            let user = UserDoc {
                id: id.to_string(),
                email: email.to_string(),
                display_name: name.to_string(),
                bc_id: format!("tester{}.bc", i + 1),
                avatar_url: String::new(),
                status_message: "บัญชีทดสอบแชท".to_string(),
                qr_token: format!("BCQR_TESTER{}", i + 1),
                role: "user".to_string(),
                department: "ทีมทดสอบ".to_string(),
                job_title: "ผู้ทดสอบระบบ".to_string(),
                google_id: None,
                created_at: now.clone(),
            };
            users_coll.insert_one(&user).await.map_err(|e| e.to_string())?;
        }
    }

    // Everyone is friends with everyone, so 1-1 chats can be opened too.
    for (a, ..) in TEST_ACCOUNTS.iter() {
        for (b, ..) in TEST_ACCOUNTS.iter() {
            if a < b {
                ensure_friendship_pair(state, a, b, false).await?;
            }
        }
    }

    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let exists = conv_coll
        .find_one(doc! { "_id": TEST_CHAT_ROOM_ID })
        .await
        .map_err(|e| e.to_string())?
        .is_some();
    if exists {
        return Ok(());
    }

    let mut member_ids: Vec<String> = TEST_ACCOUNTS.iter().map(|(id, ..)| id.to_string()).collect();
    member_ids.push("user_ai".to_string());
    let room = ConversationDoc {
        id: TEST_CHAT_ROOM_ID.to_string(),
        conv_type: "group".to_string(),
        name: "ห้องทดสอบแชท 5 คน".to_string(),
        avatar_url: String::new(),
        folder: "work".to_string(),
        is_pinned: true,
        member_ids,
        user_meta: HashMap::new(),
        pinned_message: None,
        last_message: None,
        created_at: now.clone(),
        updated_at: now,
    };
    conv_coll.insert_one(room).await.map_err(|e| e.to_string())?;
    Ok(())
}

pub async fn ensure_friendship_pair(
    state: &AppState,
    uid_a: &str,
    uid_b: &str,
    fav_a: bool,
) -> Result<(), String> {
    if uid_a == uid_b {
        return Ok(());
    }
    let friends_coll = state.db.collection::<FriendshipDoc>("friendships");
    let now = Utc::now().to_rfc3339();

    if friends_coll
        .find_one(doc! { "user_id": uid_a, "friend_id": uid_b })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let f1 = FriendshipDoc {
            id: Uuid::new_v4().to_string(),
            user_id: uid_a.to_string(),
            friend_id: uid_b.to_string(),
            is_favorite: fav_a,
            created_at: now.clone(),
        };
        let _ = friends_coll.insert_one(f1).await;
    }

    if friends_coll
        .find_one(doc! { "user_id": uid_b, "friend_id": uid_a })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let f2 = FriendshipDoc {
            id: Uuid::new_v4().to_string(),
            user_id: uid_b.to_string(),
            friend_id: uid_a.to_string(),
            is_favorite: false,
            created_at: now,
        };
        let _ = friends_coll.insert_one(f2).await;
    }

    Ok(())
}

pub async fn ensure_direct_conversation(
    state: &AppState,
    user: &UserDoc,
    partner: &UserDoc,
    conv_type: &str,
    folder: &str,
    is_pinned: bool,
    welcome_text: &str,
) -> Result<ConversationDoc, String> {
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let msg_coll = state.db.collection::<MessageDoc>("messages");

    if let Some(existing) = conv_coll
        .find_one(doc! {
            "type": { "$in": ["direct", "official"] },
            "member_ids": { "$all": [&user.id, &partner.id], "$size": 2 }
        })
        .await
        .map_err(|e| e.to_string())?
    {
        return Ok(existing);
    }

    let now = Utc::now().to_rfc3339();
    let conv_id = Uuid::new_v4().to_string();
    let msg_id = Uuid::new_v4().to_string();

    let last_msg = LastMessageSummary {
        id: msg_id.clone(),
        sender_id: partner.id.clone(),
        sender_name: partner.display_name.clone(),
        msg_type: "text".to_string(),
        content: welcome_text.to_string(),
        created_at: now.clone(),
        read_count: 0,
    };

    let conv = ConversationDoc {
        id: conv_id.clone(),
        conv_type: conv_type.to_string(),
        name: partner.display_name.clone(),
        avatar_url: partner.avatar_url.clone(),
        folder: folder.to_string(),
        is_pinned,
        member_ids: vec![user.id.clone(), partner.id.clone()],
        user_meta: HashMap::new(),
        pinned_message: None,
        last_message: Some(last_msg),
        created_at: now.clone(),
        updated_at: now.clone(),
    };

    conv_coll
        .insert_one(&conv)
        .await
        .map_err(|e| e.to_string())?;

    let msg = MessageDoc {
        id: msg_id,
        conversation_id: conv_id,
        sender_id: partner.id.clone(),
        sender_name: partner.display_name.clone(),
        sender_avatar: partner.avatar_url.clone(),
        msg_type: "text".to_string(),
        content: welcome_text.to_string(),
        sticker_code: None,
        attachment: None,
        flex_payload: None,
        reply_to: None,
        read_by: vec![partner.id.clone()],
        is_unsent: false,
        is_confidential: false,
        confidential_pin: None,
        expire_at: None,
        priority: "normal".to_string(),
        task_status: None,
        accepted_by: None,
        accepted_at: None,
        created_at: now,
    };

    msg_coll
        .insert_one(msg)
        .await
        .map_err(|e| e.to_string())?;

    Ok(conv)
}

pub async fn ensure_user_onboarding(state: &AppState, user: &UserDoc) -> Result<(), String> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let notes_coll = state.db.collection::<NoteDoc>("notes");

    let starter_contacts = vec![
        (
            "user_ai",
            "official",
            "work",
            true,
            true,
            "สวัสดีครับ! ผมคือ 🤖 BC AI (ขับเคลื่อนด้วยสมองกล DeepSeek) ผู้ช่วยประจำตัวคุณและทุกกลุ่มแชท พิมพ์ถามงานในห้องนี้ หรือพิมพ์ @ai ในกลุ่มแชทเพื่อให้ช่วยสรุปประชุม ร่างใบเสนอราคา หรือเกลาข้อความได้เลยครับ!",
        ),
        (
            "user_official",
            "official",
            "work",
            true,
            true,
            "ยินดีต้อนรับสู่ BC Super App (Enterprise)! ซิงค์แชทข้ามเครื่องด้วย Gmail 100%, รูปและไฟล์เก็บถาวรบน MinIO พร้อมโหมดความลับองค์กร ส่งผิดลบทำลายไฟล์ได้ทันทีครับ",
        ),
        (
            "user_somchai",
            "direct",
            "work",
            false,
            true,
            "สวัสดีครับ หากต้องการออกใบเสนอราคาด่วน กดปุ่ม Mini-App ในห้องแชทนี้แล้วส่งการ์ดเข้ามาได้เลยครับ!",
        ),
        (
            "user_nida",
            "direct",
            "personal",
            false,
            false,
            "สวัสดีค่ะ ส่งรูปบิลหรือไฟล์เอกสารใบกำกับภาษีในแชทนี้ได้เลยนะคะ ไฟล์เก็บถาวรในคลัง และถ้าส่งผิดสามารถกดลบทำลายออกจากเซิร์ฟเวอร์ได้ทันทีค่ะ",
        ),
        (
            "user_jead",
            "direct",
            "work",
            false,
            true,
            "ยินดีต้อนรับทีมงานทุกคนเข้าสู่ระบบ BC Super App สำหรับองค์กรครับ",
        ),
    ];

    for (contact_id, conv_type, folder, is_pinned, is_fav, welcome) in starter_contacts {
        if contact_id == user.id {
            continue;
        }
        ensure_friendship_pair(state, &user.id, contact_id, is_fav).await?;
        if let Some(partner) = users_coll
            .find_one(doc! { "_id": contact_id })
            .await
            .map_err(|e| e.to_string())?
        {
            ensure_direct_conversation(
                state,
                user,
                &partner,
                conv_type,
                folder,
                is_pinned,
                welcome,
            )
            .await?;
        }
    }

    // Ensure user is a member of "conv_group_office"
    let _ = conv_coll
        .update_one(
            doc! { "_id": "conv_group_office" },
            doc! { "$addToSet": { "member_ids": &user.id } },
        )
        .await;

    // Ensure initial Keep note and Group note exist
    let now = Utc::now().to_rfc3339();
    if notes_coll
        .find_one(doc! { "owner_id": &user.id, "conversation_id": null })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let keep_note = NoteDoc {
            id: Uuid::new_v4().to_string(),
            conversation_id: None,
            owner_id: user.id.clone(),
            owner_name: user.display_name.clone(),
            title: "รหัสประจำตัวผู้เสียภาษีและเลขบัญชีบริษัท (Keep ถาวร)".to_string(),
            content: "บจก. บีซี ซุปเปอร์แอพ (สำนักงานใหญ่)\nเลขผู้เสียภาษี: 0105566099887\nธ.กสิกรไทย: 099-8-12345-6\n(บันทึกใน BC Keep ซิงค์อัตโนมัติทุกอุปกรณ์ด้วย Gmail)".to_string(),
            attachments: vec![],
            is_pinned: true,
            created_at: now.clone(),
            updated_at: now.clone(),
        };
        let _ = notes_coll.insert_one(keep_note).await;
    }

    if notes_coll
        .find_one(doc! { "conversation_id": "conv_group_office" })
        .await
        .map_err(|e| e.to_string())?
        .is_none()
    {
        let group_note = NoteDoc {
            id: "note_group_office_1".to_string(),
            conversation_id: Some("conv_group_office".to_string()),
            owner_id: "user_jead".to_string(),
            owner_name: "ลุงจืด (Super Admin)".to_string(),
            title: "กติกาความปลอดภัยและความลับองค์กร (Enterprise Policy)".to_string(),
            content: "1. ไฟล์และรูปภาพในกลุ่มนี้เก็บถาวรบน MinIO ไม่หมดอายุ\n2. เอกสารสำคัญสามารถเปิดโหมด 'ข้อความลับ (Confidential)' เพื่อแสดงลายน้ำป้องกันการรั่วไหล\n3. หากส่งข้อความหรือไฟล์ผิด สามารถกดยกเลิก/ลบทำลายไฟล์ออกจาก MinIO ได้ทันที".to_string(),
            attachments: vec![],
            is_pinned: true,
            created_at: now.clone(),
            updated_at: now,
        };
        let _ = notes_coll.insert_one(group_note).await;
    }

    Ok(())
}
