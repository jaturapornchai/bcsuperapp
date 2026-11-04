use axum::{extract::State, Json};
use bson::doc;
use chrono::Utc;
use futures_util::TryStreamExt;
use serde::Deserialize;
use serde_json::{json, Value};
use std::time::Duration;
use uuid::Uuid;

use crate::{
    auth::{ApiError, AuthUser},
    models::{
        mask_secret_key, AiSettingsDoc, AiSettingsDto, ConversationDoc, LastMessageSummary,
        MessageDoc, MessageDto, UserDoc,
    },
    AppState,
};

pub async fn get_effective_ai_settings(state: &AppState) -> Result<AiSettingsDoc, String> {
    let coll = state.db.collection::<AiSettingsDoc>("ai_settings");
    if let Some(mut doc) = coll
        .find_one(doc! { "_id": "default" })
        .await
        .map_err(|e| e.to_string())?
    {
        if !state.config.deepseek_api_key.is_empty()
            && !state.config.deepseek_api_key.starts_with("your_")
            && doc.api_key != state.config.deepseek_api_key
        {
            doc.api_key = state.config.deepseek_api_key.clone();
            let _ = coll
                .update_one(
                    doc! { "_id": "default" },
                    doc! { "$set": { "api_key": &doc.api_key } },
                )
                .await;
        }
        return Ok(doc);
    }

    let default_doc = AiSettingsDoc {
        id: "default".to_string(),
        enabled: true,
        api_key: state.config.deepseek_api_key.clone(),
        model: if state.config.deepseek_model.is_empty() {
            "deepseek-chat".to_string()
        } else {
            state.config.deepseek_model.clone()
        },
        base_url: if state.config.deepseek_base_url.is_empty() {
            "https://api.deepseek.com".to_string()
        } else {
            state.config.deepseek_base_url.clone()
        },
        system_prompt: "คุณคือ BC AI (ขับเคลื่อนด้วย DeepSeek) สมองกลผู้ช่วยอัจฉริยะประจำองค์กรในระบบ BC Super App ช่วยสรุปการประชุมกลุ่ม แกะงานสำคัญ ร่างใบเสนอราคา เกลาข้อความภาษาไทยให้สุภาพเป็นทางการ และตอบคำถามอย่างกระชับ ตรงประเด็น ปลอดภัย และรักษาความลับขององค์กร".to_string(),
        auto_reply_in_groups: true,
        redact_confidential: true,
        updated_at: Utc::now().to_rfc3339(),
    };

    let _ = coll.insert_one(&default_doc).await;
    Ok(default_doc)
}

fn to_settings_dto(doc: &AiSettingsDoc) -> AiSettingsDto {
    let (has_api_key, masked_key) = mask_secret_key(&doc.api_key);
    AiSettingsDto {
        enabled: doc.enabled,
        has_api_key,
        masked_key,
        model: doc.model.clone(),
        base_url: doc.base_url.clone(),
        system_prompt: doc.system_prompt.clone(),
        auto_reply_in_groups: doc.auto_reply_in_groups,
        redact_confidential: doc.redact_confidential,
        updated_at: doc.updated_at.clone(),
    }
}

pub async fn get_ai_settings_handler(
    _auth: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<AiSettingsDto>, ApiError> {
    let settings = get_effective_ai_settings(&state)
        .await
        .map_err(ApiError::internal)?;
    Ok(Json(to_settings_dto(&settings)))
}

#[derive(Debug, Deserialize)]
pub struct UpdateAiSettingsRequest {
    pub enabled: Option<bool>,
    pub api_key: Option<String>,
    pub clear_api_key: Option<bool>,
    pub model: Option<String>,
    pub base_url: Option<String>,
    pub system_prompt: Option<String>,
    pub auto_reply_in_groups: Option<bool>,
    pub redact_confidential: Option<bool>,
}

pub async fn update_ai_settings_handler(
    _auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<UpdateAiSettingsRequest>,
) -> Result<Json<AiSettingsDto>, ApiError> {
    let mut settings = get_effective_ai_settings(&state)
        .await
        .map_err(ApiError::internal)?;

    if let Some(enabled) = payload.enabled {
        settings.enabled = enabled;
    }
    if payload.clear_api_key == Some(true) {
        settings.api_key = String::new();
    } else if let Some(ref key) = payload.api_key {
        let trimmed = key.trim();
        if !trimmed.is_empty() && !trimmed.contains("****") {
            settings.api_key = trimmed.to_string();
        }
    }
    if let Some(model) = payload.model {
        if !model.trim().is_empty() {
            settings.model = model.trim().to_string();
        }
    }
    if let Some(base_url) = payload.base_url {
        if !base_url.trim().is_empty() {
            settings.base_url = base_url.trim().trim_end_matches('/').to_string();
        }
    }
    if let Some(prompt) = payload.system_prompt {
        if !prompt.trim().is_empty() {
            settings.system_prompt = prompt.trim().to_string();
        }
    }
    if let Some(auto_group) = payload.auto_reply_in_groups {
        settings.auto_reply_in_groups = auto_group;
    }
    if let Some(redact) = payload.redact_confidential {
        settings.redact_confidential = redact;
    }
    settings.updated_at = Utc::now().to_rfc3339();

    let coll = state.db.collection::<AiSettingsDoc>("ai_settings");
    coll.replace_one(doc! { "_id": "default" }, &settings)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    Ok(Json(to_settings_dto(&settings)))
}

pub async fn call_deepseek_brain(
    state: &AppState,
    custom_system_prompt: Option<&str>,
    user_prompt: &str,
    history: &[MessageDoc],
) -> (String, String, bool) {
    let settings = match get_effective_ai_settings(state).await {
        Ok(s) => s,
        Err(_) => {
            let fallback = generate_smart_context_reply(user_prompt, history);
            return (fallback, "deepseek-chat".to_string(), false);
        }
    };

    let (has_key, _) = mask_secret_key(&settings.api_key);
    let sys_prompt = custom_system_prompt.unwrap_or(&settings.system_prompt);

    if has_key && settings.enabled {
        let mut api_messages = vec![json!({
            "role": "system",
            "content": sys_prompt,
        })];

        for m in history.iter().rev().take(15).rev() {
            if m.is_unsent {
                continue;
            }
            let content_text = if settings.redact_confidential && m.confidential_pin.is_some() {
                "[ข้อความความลับองค์กรที่ล็อกด้วยรหัส PIN - ปกปิดข้อมูลอัตโนมัติ]".to_string()
            } else {
                format!("{}: {}", m.sender_name, m.content)
            };
            let role = if m.sender_id == "user_ai" {
                "assistant"
            } else {
                "user"
            };
            api_messages.push(json!({
                "role": role,
                "content": content_text,
            }));
        }

        api_messages.push(json!({
            "role": "user",
            "content": user_prompt,
        }));

        let endpoint = if settings.base_url.ends_with("/v1") {
            format!("{}/chat/completions", settings.base_url)
        } else {
            format!("{}/v1/chat/completions", settings.base_url)
        };

        let req_body = json!({
            "model": settings.model,
            "messages": api_messages,
            "temperature": 0.4,
            "max_tokens": 1024,
        });

        if let Ok(resp) = state
            .minio
            .http
            .post(&endpoint)
            .timeout(Duration::from_secs(25))
            .header("Authorization", format!("Bearer {}", settings.api_key))
            .header("Content-Type", "application/json")
            .json(&req_body)
            .send()
            .await
        {
            if resp.status().is_success() {
                if let Ok(val) = resp.json::<Value>().await {
                    if let Some(reply) = val
                        .get("choices")
                        .and_then(|c| c.get(0))
                        .and_then(|c| c.get("message"))
                        .and_then(|m| m.get("content"))
                        .and_then(|t| t.as_str())
                    {
                        return (reply.trim().to_string(), settings.model, true);
                    }
                }
            }
        }
    }

    let smart_reply = generate_smart_context_reply(user_prompt, history);
    (smart_reply, settings.model, false)
}

fn generate_smart_context_reply(user_prompt: &str, history: &[MessageDoc]) -> String {
    let clean_prompt = user_prompt
        .replace("@ai", "")
        .replace("@AI", "")
        .replace("@bc", "")
        .replace("@BC", "")
        .trim()
        .to_string();

    let lower = clean_prompt.to_lowercase();

    let active_msgs: Vec<&MessageDoc> = history
        .iter()
        .filter(|m| !m.is_unsent && m.sender_id != "user_ai")
        .collect();

    let mut participants: Vec<String> = Vec::new();
    let mut files_mentioned: Vec<String> = Vec::new();
    for m in &active_msgs {
        if !participants.contains(&m.sender_name) {
            participants.push(m.sender_name.clone());
        }
        if let Some(ref att) = m.attachment {
            files_mentioned.push(format!("{} (โดย {})", att.file_name, m.sender_name));
        }
    }

    if lower.contains("สรุป") || lower.contains("summary") || lower.contains("ประชุม") {
        let mut lines = Vec::new();
        lines.push("📊 **สรุปสาระสำคัญของห้องแชทโดยสมองกล DeepSeek AI**:".to_string());
        if active_msgs.is_empty() {
            lines.push("• ยังไม่มีข้อความสนทนาก่อนหน้าในห้องนี้".to_string());
        } else {
            lines.push(format!(
                "• **ผู้ร่วมสนทนา ({} ท่าน)**: {}",
                participants.len(),
                participants.join(", ")
            ));
            for m in active_msgs.iter().rev().take(4).rev() {
                let snippet: String = m.content.chars().take(90).collect();
                lines.push(format!("• **{}**: {}", m.sender_name, snippet));
            }
            if !files_mentioned.is_empty() {
                lines.push(format!(
                    "• **ไฟล์/เอกสารสำคัญในคลัง MinIO**: {}",
                    files_mentioned.join(", ")
                ));
            }
            lines.push("✅ **Action Items แนะนำ**: ตรวจสอบเอกสารที่แนบในคลังไฟล์ถาวร และยืนยันการอนุมัติผ่านการ์ด Mini-App ในห้องแชท".to_string());
        }
        return lines.join("\n");
    }

    if lower.contains("ใบเสนอราคา") || lower.contains("ราคา") || lower.contains("quotation") {
        return "📝 **ร่างข้อความใบเสนอราคาโดย DeepSeek AI**:\n\"เรียน ลูกค้าผู้มีอุปการคุณ\nขออนุญาตจัดส่งใบเสนอราคาชุดซอฟต์แวร์ BC Super App Enterprise พร้อมระบบจัดเก็บไฟล์ถาวรและสมองกล AI ประจำองค์กร ยอดสุทธิรวมภาษีมูลค่าเพิ่ม 48,150.00 บาท ทั้งนี้ท่านสามารถกดดูรายละเอียดจากคลังไฟล์ในแชทนี้ได้ตลอดเวลาโดยไฟล์ไม่มีวันหมดอายุครับ\"".to_string();
    }

    if lower.contains("ความลับ") || lower.contains("ส่งผิด") || lower.contains("ลบ") {
        return "🔒 **คำแนะนำด้านความปลอดภัยองค์กรจาก DeepSeek AI**:\n1. ก่อนส่งไฟล์สำคัญ ให้เปิดปุ่ม **'โหมดความลับ (Confidential)'** และตั้งรหัส PIN 4 หลัก\n2. หากส่งข้อความหรือไฟล์ผิดห้อง สามารถกด **'ลบทำลายไฟล์ทันที (Purge)'** ระบบจะลบไฟล์ออกจาก MinIO Object Storage และลบข้อความออกจากเครื่องสมาชิกทุกคนแบบ Real-time ทันทีครับ".to_string();
    }

    let recent_context = active_msgs
        .last()
        .map(|m| format!("(อ้างอิงข้อความล่าสุดของ {}: \"{}\")", m.sender_name, m.content))
        .unwrap_or_default();

    format!(
        "🤖 **BC AI (DeepSeek Assistant)** ขอตอบคำถามเรื่อง **\"{}\"** ครับ:\n• วิเคราะห์จากบริบทห้องแชท {}\n• **ข้อเสนอแนะ**: สามารถดำเนินการต่อได้ทันที โดยหากต้องการส่งเอกสารอนุมัติ (ใบลา / ใบเสนอราคา / เบิกบิล) แนะนำให้กดปุ่ม **Mini-App** ด้านล่างช่องแชทเพื่อส่งเป็น Rich Card หรือพิมพ์ `@ai สรุป` เพื่อให้ผมสรุปประเด็นทั้งหมดในห้องนี้ครับ",
        if clean_prompt.is_empty() {
            "ขอคำแนะนำในห้องแชท"
        } else {
            &clean_prompt
        },
        recent_context
    )
}

#[derive(Debug, Deserialize)]
pub struct SummarizeRequest {
    pub conversation_id: String,
    pub post_to_chat: Option<bool>,
}

pub async fn summarize_conversation_handler(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<SummarizeRequest>,
) -> Result<Json<Value>, ApiError> {
    let msg_coll = state.db.collection::<MessageDoc>("messages");

    let mut conv = crate::routes::chat_routes::require_member(
        &state,
        payload.conversation_id.trim(),
        &auth.user_id,
    )
    .await?;

    let cursor = msg_coll
        .find(doc! { "conversation_id": &conv.id, "is_unsent": false })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let mut history: Vec<MessageDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    history.sort_by(|a, b| a.created_at.cmp(&b.created_at));

    let prompt = "กรุณาสรุปสาระสำคัญของการสนทนาในห้องแชทนี้ แยกเป็นประเด็นสำคัญ, สิ่งที่ต้องทำต่อ (Action Items), และข้อตกลงร่วมกัน";
    let (summary_text, model, live_api) =
        call_deepseek_brain(&state, None, prompt, &history).await;

    let mut participants = Vec::new();
    let mut action_items = Vec::new();
    let mut decisions = Vec::new();

    for m in &history {
        if m.sender_id != "user_ai" && !participants.contains(&m.sender_name) {
            participants.push(m.sender_name.clone());
        }
        if let Some(ref att) = m.attachment {
            action_items.push(format!(
                "ตรวจสอบไฟล์ '{}' ที่ส่งโดย {}",
                att.file_name, m.sender_name
            ));
        }
    }

    if action_items.is_empty() {
        action_items.push("ติดตามความคืบหน้างานตามที่แจ้งในห้องแชท".to_string());
    }
    action_items.push("บันทึกข้อมูลสำคัญเก็บเข้าสมุดโน้ตกลุ่ม (BC Keep) หรือคลังไฟล์ถาวร".to_string());

    if let Some(ref pinned) = conv.pinned_message {
        decisions.push(format!("ประกาศปักหมุดของห้อง: {}", pinned.content));
    }
    decisions.push("ใช้ระบบคลังไฟล์ถาวร MinIO และโหมดความลับองค์กรสำหรับการรับ-ส่งเอกสาร".to_string());

    if payload.post_to_chat == Some(true) {
        let _ = insert_ai_message(&state, &mut conv, &summary_text).await;
    }

    Ok(Json(json!({
        "conversation_id": conv.id,
        "conversation_name": conv.name,
        "summary": summary_text,
        "action_items": action_items,
        "decisions": decisions,
        "participants": participants,
        "message_count": history.len(),
        "model": model,
        "live_api": live_api,
    })))
}

#[derive(Debug, Deserialize)]
pub struct AssistRequest {
    pub conversation_id: Option<String>,
    pub prompt: Option<String>,
    pub mode: Option<String>, // "polish" | "formal" | "suggest_reply" | "translate_en" | "action_plan"
}

pub async fn assist_message_handler(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<AssistRequest>,
) -> Result<Json<Value>, ApiError> {
    let mode = payload
        .mode
        .unwrap_or_else(|| "polish".to_string())
        .to_lowercase();
    let raw_prompt = payload.prompt.unwrap_or_default().trim().to_string();

    let mut history: Vec<MessageDoc> = Vec::new();
    if let Some(ref cid) = payload.conversation_id {
        if !cid.trim().is_empty() {
            crate::routes::chat_routes::require_member(&state, cid.trim(), &auth.user_id).await?;
            let msg_coll = state.db.collection::<MessageDoc>("messages");
            if let Ok(cursor) = msg_coll
                .find(doc! { "conversation_id": cid.trim(), "is_unsent": false })
                .await
            {
                if let Ok(mut docs) = cursor.try_collect::<Vec<MessageDoc>>().await {
                    docs.sort_by(|a, b| a.created_at.cmp(&b.created_at));
                    history = docs;
                }
            }
        }
    }

    let settings = get_effective_ai_settings(&state)
        .await
        .map_err(ApiError::internal)?;
    let (has_key, _) = mask_secret_key(&settings.api_key);

    let (result_text, suggestions, live_api) = if has_key && settings.enabled {
        let instruction = match mode.as_str() {
            "formal" | "polish" => format!(
                "ช่วยเกลาข้อความต่อไปนี้ให้เป็นภาษาไทยระดับองค์กรที่สุภาพ เป็นทางการ และกระชับ (ส่งคืนเฉพาะข้อความที่เกลาแล้ว): {}",
                raw_prompt
            ),
            "translate_en" => format!(
                "แปลข้อความต่อไปนี้เป็นภาษาอังกฤษสำหรับติดต่อธุรกิจ (Business English): {}",
                raw_prompt
            ),
            "suggest_reply" => "จากประวัติแชทล่าสุด ช่วยแนะนำข้อความตอบกลับสั้นๆ ที่สุภาพและเป็นมืออาชีพ 3 รูปแบบ".to_string(),
            "action_plan" => format!(
                "ช่วยแตกแผนงาน (Action Plan) เป็นข้อๆ จากหัวข้อต่อไปนี้: {}",
                raw_prompt
            ),
            _ => raw_prompt.clone(),
        };

        let (reply, _, is_live) = call_deepseek_brain(&state, None, &instruction, &history).await;
        let suggs = vec![
            "รับทราบครับ เดี๋ยวรีบดำเนินการตรวจสอบและแจ้งผลกลับภายในวันนี้ครับ".to_string(),
            "ขอบคุณสำหรับข้อมูลครับ ได้รับไฟล์เอกสารในคลังถาวรเรียบร้อยแล้วครับ".to_string(),
            "เห็นด้วยตามข้อเสนอครับ สามารถส่งการ์ดขออนุมัติผ่าน Mini-App เข้ามาได้เลยครับ".to_string(),
        ];
        (reply, suggs, is_live)
    } else {
        match mode.as_str() {
            "formal" | "polish" => {
                let polished = if raw_prompt.is_empty() {
                    "เรียนทีมงานทุกท่าน ขออนุญาตแจ้งอัปเดตความคืบหน้าของงานและเอกสารที่เกี่ยวข้องในห้องแชทนี้ครับ".to_string()
                } else {
                    format!(
                        "เรียนผู้เกี่ยวข้อง ขออนุญาตแจ้งรายละเอียดดังนี้ครับ: {} จึงเรียนมาเพื่อโปรดพิจารณาและดำเนินการในส่วนที่เกี่ยวข้องต่อไป ขอบคุณครับ",
                        raw_prompt
                    )
                };
                let suggs = vec![
                    polished.clone(),
                    format!("ขออนุญาตนำส่งข้อมูล: {} หากมีข้อสงสัยเพิ่มเติมสามารถสอบถามได้ทันทีครับ", raw_prompt),
                    format!("แจ้งเพื่อทราบ: {} รบกวนตรวจสอบเอกสารแนบในคลังไฟล์ครับ", raw_prompt),
                ];
                (polished, suggs, false)
            }
            "translate_en" => {
                let translated = if raw_prompt.is_empty() {
                    "Dear Team, please find the attached documents in our permanent vault for your review.".to_string()
                } else {
                    format!(
                        "Dear Team, regarding \"{}\" — please review the details and confirm at your earliest convenience. Best regards.",
                        raw_prompt
                    )
                };
                let suggs = vec![translated.clone()];
                (translated, suggs, false)
            }
            "suggest_reply" => {
                let last_sender = history
                    .iter()
                    .rev()
                    .find(|m| m.sender_id != "user_ai")
                    .map(|m| m.sender_name.clone())
                    .unwrap_or_else(|| "ทีมงาน".to_string());
                let s1 = format!("รับทราบครับคุณ{} เดี๋ยวผมตรวจสอบเอกสารในคลังไฟล์แล้วแจ้งกลับทันทีครับ", last_sender);
                let s2 = "ได้รับเอกสารใบกำกับภาษี/ใบเสนอราคาเรียบร้อยแล้ว ขอบคุณมากครับ".to_string();
                let s3 = "อนุมัติรายการตามที่แจ้งครับ สามารถเปิดการ์ดใน Mini-App เพื่อดำเนินการต่อได้เลยครับ".to_string();
                (s1.clone(), vec![s1, s2, s3], false)
            }
            _ => {
                let (reply, _, _) = call_deepseek_brain(&state, None, &raw_prompt, &history).await;
                let suggs = vec![
                    "รับทราบครับ เดี๋ยวรีบดำเนินการให้ทันทีครับ".to_string(),
                    "ขอบคุณครับ ตรวจสอบไฟล์ในคลังเรียบร้อยแล้วครับ".to_string(),
                ];
                (reply, suggs, false)
            }
        }
    };

    Ok(Json(json!({
        "mode": mode,
        "result": result_text,
        "suggestions": suggestions,
        "model": settings.model,
        "live_api": live_api,
    })))
}

pub async fn insert_ai_message(
    state: &AppState,
    conv: &mut ConversationDoc,
    ai_text: &str,
) -> Result<MessageDto, String> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let msg_coll = state.db.collection::<MessageDoc>("messages");
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");

    let ai_user = users_coll
        .find_one(doc! { "_id": "user_ai" })
        .await
        .ok()
        .flatten()
        .unwrap_or_else(|| UserDoc {
            id: "user_ai".to_string(),
            email: "ai@bcapp.local".to_string(),
            display_name: "🤖 BC AI (DeepSeek Assistant)".to_string(),
            bc_id: "@bc.ai".to_string(),
            avatar_url: "https://ui-avatars.com/api/?name=BC+AI&background=4F46E5&color=fff&bold=true".to_string(),
            status_message: "สมองกล DeepSeek ผู้ช่วยทุกคนและทุกกลุ่ม".to_string(),
            qr_token: "BCQR_DEEPSEEK_AI".to_string(),
            role: "admin".to_string(),
            department: "AI Brain".to_string(),
            job_title: "สมองกลผู้ช่วยประจำทุกคนและทุกกลุ่ม".to_string(),
            google_id: None,
            created_at: Utc::now().to_rfc3339(),
        });

    let now = Utc::now().to_rfc3339();
    let msg_id = Uuid::new_v4().to_string();

    let ai_msg = MessageDoc {
        id: msg_id.clone(),
        conversation_id: conv.id.clone(),
        sender_id: ai_user.id.clone(),
        sender_name: ai_user.display_name.clone(),
        sender_avatar: ai_user.avatar_url.clone(),
        msg_type: "text".to_string(),
        content: ai_text.to_string(),
        sticker_code: None,
        attachment: None,
        flex_payload: None,
        reply_to: None,
        read_by: vec![ai_user.id.clone()],
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

    msg_coll
        .insert_one(&ai_msg)
        .await
        .map_err(|e| e.to_string())?;

    conv.last_message = Some(LastMessageSummary {
        id: msg_id,
        sender_id: ai_user.id,
        sender_name: ai_user.display_name,
        msg_type: "text".to_string(),
        content: ai_text.chars().take(120).collect(),
        created_at: now.clone(),
        read_count: 0,
    });
    conv.updated_at = now;

    let _ = conv_coll
        .replace_one(doc! { "_id": &conv.id }, &*conv)
        .await;

    let dto = MessageDto::from(ai_msg);
    state.ws_hub.broadcast_event(json!({
        "event": "new_message",
        "conversation_id": conv.id,
        "message": dto,
    }));

    Ok(dto)
}

pub async fn maybe_trigger_ai_reply(
    state: &AppState,
    conv: &mut ConversationDoc,
    trigger_msg: &MessageDoc,
) -> Option<MessageDto> {
    if trigger_msg.sender_id == "user_ai" || trigger_msg.is_unsent {
        return None;
    }

    let is_direct_with_ai =
        conv.member_ids.len() == 2 && conv.member_ids.iter().any(|id| id == "user_ai");
    let lower_content = trigger_msg.content.to_lowercase();
    let is_mentioned = lower_content.contains("@ai")
        || lower_content.contains("@bc.ai")
        || lower_content.contains("/ai")
        || lower_content.contains("บีซีเอไอ");

    if !is_direct_with_ai && !is_mentioned {
        return None;
    }

    let msg_coll = state.db.collection::<MessageDoc>("messages");
    let mut history: Vec<MessageDoc> = match msg_coll
        .find(doc! { "conversation_id": &conv.id, "is_unsent": false })
        .await
    {
        Ok(cursor) => cursor.try_collect().await.unwrap_or_default(),
        Err(_) => vec![],
    };
    history.sort_by(|a, b| a.created_at.cmp(&b.created_at));

    let (ai_reply_text, _, _) =
        call_deepseek_brain(state, None, &trigger_msg.content, &history).await;

    insert_ai_message(state, conv, &ai_reply_text).await.ok()
}
