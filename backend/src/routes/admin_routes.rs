use axum::{
    extract::{Path, State},
    Json,
};
use bson::doc;
use chrono::Utc;
use futures_util::TryStreamExt;
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{
    auth::{ApiError, AuthUser},
    models::{
        ConversationDoc, FileDoc, FileDto, LastMessageSummary, MessageDoc, MessageDto, MiniAppDoc,
        MiniAppDto, UserDoc, UserDto,
    },
    seed::ensure_direct_conversation,
    AppState,
};

pub async fn admin_overview_handler(
    _auth: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, ApiError> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let msg_coll = state.db.collection::<MessageDoc>("messages");
    let files_coll = state.db.collection::<FileDoc>("files");
    let mini_coll = state.db.collection::<MiniAppDoc>("mini_apps");

    let total_users = users_coll.count_documents(doc! {}).await.unwrap_or(0);
    let total_conversations = conv_coll.count_documents(doc! {}).await.unwrap_or(0);
    let total_messages = msg_coll.count_documents(doc! {}).await.unwrap_or(0);
    let total_mini_apps = mini_coll.count_documents(doc! {}).await.unwrap_or(0);

    let file_cursor = files_coll
        .find(doc! {})
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let mut all_files: Vec<FileDoc> = file_cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let total_files = all_files.len() as u64;
    let total_storage_bytes: u64 = all_files.iter().map(|f| f.file_size).sum();

    all_files.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    let recent_files: Vec<FileDto> = all_files.into_iter().take(20).map(FileDto::from).collect();

    Ok(Json(json!({
        "total_users": total_users,
        "total_conversations": total_conversations,
        "total_messages": total_messages,
        "total_files": total_files,
        "total_storage_bytes": total_storage_bytes,
        "total_mini_apps": total_mini_apps,
        "recent_files": recent_files,
    })))
}

pub async fn admin_list_users_handler(
    _auth: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Vec<UserDto>>, ApiError> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let cursor = users_coll
        .find(doc! {})
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let mut docs: Vec<UserDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    docs.sort_by(|a, b| a.display_name.cmp(&b.display_name));
    Ok(Json(docs.into_iter().map(UserDto::from).collect()))
}

#[derive(Debug, Deserialize)]
pub struct UpdateRoleRequest {
    pub role: String,
}

pub async fn admin_update_user_role_handler(
    _auth: AuthUser,
    Path(user_id): Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<UpdateRoleRequest>,
) -> Result<Json<UserDto>, ApiError> {
    let role = if payload.role.trim().eq_ignore_ascii_case("admin") {
        "admin".to_string()
    } else {
        "user".to_string()
    };

    let users_coll = state.db.collection::<UserDoc>("users");
    let mut user = users_coll
        .find_one(doc! { "_id": &user_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบผู้ใช้ที่ระบุ"))?;

    user.role = role.clone();
    users_coll
        .update_one(
            doc! { "_id": &user_id },
            doc! { "$set": { "role": &role } },
        )
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    Ok(Json(UserDto::from(user)))
}

pub async fn admin_list_mini_apps_handler(
    _auth: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Vec<MiniAppDto>>, ApiError> {
    let coll = state.db.collection::<MiniAppDoc>("mini_apps");
    let cursor = coll
        .find(doc! {})
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let mut docs: Vec<MiniAppDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    docs.sort_by_key(|a| a.sort_order);
    Ok(Json(docs.into_iter().map(MiniAppDto::from).collect()))
}

#[derive(Debug, Deserialize)]
pub struct CreateMiniAppRequest {
    pub app_code: Option<String>,
    pub title: String,
    pub subtitle: Option<String>,
    pub category: Option<String>,
    pub icon_name: Option<String>,
    pub color_hex: Option<String>,
    pub entry_url: Option<String>,
    pub is_active: Option<bool>,
    pub sort_order: Option<i32>,
}

pub async fn admin_create_mini_app_handler(
    _auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<CreateMiniAppRequest>,
) -> Result<Json<MiniAppDto>, ApiError> {
    let title = payload.title.trim().to_string();
    if title.is_empty() {
        return Err(ApiError::bad_request("กรุณาระบุชื่อบริการ Mini-App"));
    }

    let app_code = payload
        .app_code
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| format!("app_{}", &Uuid::new_v4().simple().to_string()[..8]));

    let entry_url = payload
        .entry_url
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| format!("{}/miniapp/{}", state.config.public_base_url, app_code));

    let now = Utc::now().to_rfc3339();
    let doc_item = MiniAppDoc {
        id: format!("mini_{}", &Uuid::new_v4().simple().to_string()[..10]),
        app_code,
        title,
        subtitle: payload
            .subtitle
            .unwrap_or_else(|| "บริการเสริม WebView อัปเดตสดจากหลังบ้าน".to_string()),
        category: payload.category.unwrap_or_else(|| "work".to_string()),
        icon_name: payload.icon_name.unwrap_or_else(|| "widgets".to_string()),
        color_hex: payload.color_hex.unwrap_or_else(|| "#06C755".to_string()),
        entry_url,
        is_active: payload.is_active.unwrap_or(true),
        sort_order: payload.sort_order.unwrap_or(10),
        created_at: now.clone(),
        updated_at: now,
    };

    let coll = state.db.collection::<MiniAppDoc>("mini_apps");
    coll.insert_one(&doc_item)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let dto = MiniAppDto::from(doc_item);
    state.ws_hub.broadcast_event(json!({
        "event": "mini_apps_updated",
        "mini_app": dto,
    }));

    Ok(Json(dto))
}

#[derive(Debug, Deserialize)]
pub struct UpdateMiniAppRequest {
    pub app_code: Option<String>,
    pub title: Option<String>,
    pub subtitle: Option<String>,
    pub category: Option<String>,
    pub icon_name: Option<String>,
    pub color_hex: Option<String>,
    pub entry_url: Option<String>,
    pub is_active: Option<bool>,
    pub sort_order: Option<i32>,
}

pub async fn admin_update_mini_app_handler(
    _auth: AuthUser,
    Path(app_id): Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<UpdateMiniAppRequest>,
) -> Result<Json<MiniAppDto>, ApiError> {
    let coll = state.db.collection::<MiniAppDoc>("mini_apps");
    let mut app = coll
        .find_one(doc! { "_id": &app_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบ Mini-App ที่ระบุ"))?;

    if let Some(code) = payload.app_code {
        if !code.trim().is_empty() {
            app.app_code = code.trim().to_string();
        }
    }
    if let Some(title) = payload.title {
        if !title.trim().is_empty() {
            app.title = title.trim().to_string();
        }
    }
    if let Some(sub) = payload.subtitle {
        app.subtitle = sub.trim().to_string();
    }
    if let Some(cat) = payload.category {
        if !cat.trim().is_empty() {
            app.category = cat.trim().to_string();
        }
    }
    if let Some(icon) = payload.icon_name {
        if !icon.trim().is_empty() {
            app.icon_name = icon.trim().to_string();
        }
    }
    if let Some(color) = payload.color_hex {
        if !color.trim().is_empty() {
            app.color_hex = color.trim().to_string();
        }
    }
    if let Some(url) = payload.entry_url {
        if !url.trim().is_empty() {
            app.entry_url = url.trim().to_string();
        }
    }
    if let Some(active) = payload.is_active {
        app.is_active = active;
    }
    if let Some(order) = payload.sort_order {
        app.sort_order = order;
    }
    app.updated_at = Utc::now().to_rfc3339();

    coll.replace_one(doc! { "_id": &app_id }, &app)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let dto = MiniAppDto::from(app);
    state.ws_hub.broadcast_event(json!({
        "event": "mini_apps_updated",
        "mini_app": dto,
    }));

    Ok(Json(dto))
}

pub async fn admin_delete_mini_app_handler(
    _auth: AuthUser,
    Path(app_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<Value>, ApiError> {
    let coll = state.db.collection::<MiniAppDoc>("mini_apps");
    coll.delete_one(doc! { "_id": &app_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    state.ws_hub.broadcast_event(json!({
        "event": "mini_apps_updated",
        "deleted_id": app_id,
    }));

    Ok(Json(json!({
        "status": "ok",
        "id": app_id,
    })))
}

#[derive(Debug, Deserialize)]
pub struct BroadcastRequest {
    pub title: String,
    pub content: String,
}

pub async fn admin_broadcast_handler(
    _auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<BroadcastRequest>,
) -> Result<Json<Value>, ApiError> {
    let title = payload.title.trim().to_string();
    let content = payload.content.trim().to_string();
    if title.is_empty() && content.is_empty() {
        return Err(ApiError::bad_request("กรุณาระบุข้อความประกาศ"));
    }

    let users_coll = state.db.collection::<UserDoc>("users");
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let msg_coll = state.db.collection::<MessageDoc>("messages");

    let official = users_coll
        .find_one(doc! { "_id": "user_official" })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบบัญชี BC Official OA"))?;

    let u_cursor = users_coll
        .find(doc! { "_id": { "$ne": "user_official" } })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let all_users: Vec<UserDoc> = u_cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let formatted = if title.is_empty() {
        format!("📢 ประกาศ: {}", content)
    } else {
        format!("📢 {}\n{}", title, content)
    };

    let now = Utc::now().to_rfc3339();
    let mut sent_count = 0usize;

    for u in all_users {
        if let Ok(mut conv) = ensure_direct_conversation(
            &state,
            &u,
            &official,
            "official",
            "work",
            true,
            &formatted,
        )
        .await
        {
            let msg_id = Uuid::new_v4().to_string();
            let msg_doc = MessageDoc {
                id: msg_id.clone(),
                conversation_id: conv.id.clone(),
                sender_id: official.id.clone(),
                sender_name: official.display_name.clone(),
                sender_avatar: official.avatar_url.clone(),
                msg_type: "flex_card".to_string(),
                content: formatted.clone(),
                sticker_code: None,
                attachment: None,
                flex_payload: Some(json!({
                    "app_code": "official_broadcast",
                    "title": "ประกาศจาก BC Official OA",
                    "color_hex": "#00B900",
                    "heading": if title.is_empty() { "แจ้งข่าวสารสำคัญ" } else { &title },
                    "subtitle": content,
                    "highlight_value": "ประกาศทางการ",
                    "status_label": "BC Official"
                })),
                reply_to: None,
                read_by: vec![official.id.clone()],
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

            if msg_coll.insert_one(&msg_doc).await.is_ok() {
                conv.last_message = Some(LastMessageSummary {
                    id: msg_id,
                    sender_id: official.id.clone(),
                    sender_name: official.display_name.clone(),
                    msg_type: "flex_card".to_string(),
                    content: formatted.clone(),
                    created_at: now.clone(),
                    read_count: 0,
                });
                conv.updated_at = now.clone();
                let _ = conv_coll
                    .replace_one(doc! { "_id": &conv.id }, &conv)
                    .await;

                let dto = MessageDto::from(msg_doc);
                state.ws_hub.broadcast_event(json!({
                    "event": "new_message",
                    "conversation_id": conv.id,
                    "message": dto,
                }));
                sent_count += 1;
            }
        }
    }

    Ok(Json(json!({
        "status": "ok",
        "sent_count": sent_count,
    })))
}

#[derive(Debug, Deserialize)]
pub struct HandoverRequest {
    pub from_user_id: String,
    pub to_user_id: String,
}

pub async fn admin_handover_handler(
    _auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<HandoverRequest>,
) -> Result<Json<Value>, ApiError> {
    let from_id = payload.from_user_id.trim();
    let to_id = payload.to_user_id.trim();
    if from_id.is_empty() || to_id.is_empty() {
        return Err(ApiError::bad_request("กรุณาระบุรหัสพนักงานเดิมและผู้รับผิดชอบคนใหม่"));
    }

    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let cursor = conv_coll
        .find(doc! { "member_ids": from_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let mut convs: Vec<ConversationDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let briefing_text = "🔄 [AI Handover Briefing] โอนย้ายการดูแลห้องแชทจากพนักงานเดิมให้ผู้รับผิดชอบคนใหม่เรียบร้อยแล้ว สามารถเปิดดูประวัติแชทและคลังไฟล์ MinIO ย้อนหลังได้ครบ 100%";
    let mut count = 0usize;

    for conv in &mut convs {
        if !conv.member_ids.iter().any(|m| m == to_id) {
            conv.member_ids.push(to_id.to_string());
        }
        let _ = crate::routes::ai_routes::insert_ai_message(&state, conv, briefing_text).await;
        count += 1;
    }

    Ok(Json(json!({
        "transferred_conversations": count,
        "status": "ok",
    })))
}
