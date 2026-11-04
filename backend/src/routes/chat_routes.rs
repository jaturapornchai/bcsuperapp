use axum::{
    extract::{Path, Query, State},
    Json,
};
use bson::{doc, Regex};
use chrono::Utc;
use futures_util::TryStreamExt;
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use uuid::Uuid;

use crate::{
    auth::{ApiError, AuthUser},
    models::{
        AttachmentInfo, ConversationDoc, ConversationDto, ConversationMemberDto, FileDoc,
        LastMessageSummary, MessageDoc, MessageDto, NoteDoc, NoteDto, PinnedMessageSummary,
        ReplyInfo, UserDoc, VaultFileItem, VaultLinkItem, VaultResponse,
    },
    seed::ensure_direct_conversation,
    AppState,
};

#[derive(Debug, Deserialize)]
pub struct ListConversationsQuery {
    pub folder: Option<String>,
}

pub async fn build_conversation_dto(
    state: &AppState,
    conv: ConversationDoc,
    current_user_id: &str,
) -> Result<ConversationDto, String> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let msg_coll = state.db.collection::<MessageDoc>("messages");

    let user_cursor = users_coll
        .find(doc! { "_id": { "$in": &conv.member_ids } })
        .await
        .map_err(|e| e.to_string())?;
    let member_docs: Vec<UserDoc> = user_cursor
        .try_collect()
        .await
        .map_err(|e| e.to_string())?;

    let members: Vec<ConversationMemberDto> = member_docs
        .iter()
        .map(|u| ConversationMemberDto {
            id: u.id.clone(),
            email: u.email.clone(),
            display_name: u.display_name.clone(),
            bc_id: u.bc_id.clone(),
            avatar_url: u.avatar_url.clone(),
            status_message: u.status_message.clone(),
            role: u.role.clone(),
            department: if u.department.is_empty() {
                "ทั่วไป".to_string()
            } else {
                u.department.clone()
            },
            job_title: if u.job_title.is_empty() {
                "พนักงาน".to_string()
            } else {
                u.job_title.clone()
            },
        })
        .collect();

    let (resolved_name, resolved_avatar) =
        if conv.conv_type == "direct" || conv.conv_type == "official" {
            if let Some(other) = member_docs.iter().find(|u| u.id != current_user_id) {
                (other.display_name.clone(), other.avatar_url.clone())
            } else {
                (conv.name.clone(), conv.avatar_url.clone())
            }
        } else {
            (conv.name.clone(), conv.avatar_url.clone())
        };

    let (folder, is_pinned) = if let Some(meta) = conv.user_meta.get(current_user_id) {
        (meta.folder.clone(), meta.is_pinned)
    } else {
        (conv.folder.clone(), conv.is_pinned)
    };

    let unread_count = msg_coll
        .count_documents(doc! {
            "conversation_id": &conv.id,
            "sender_id": { "$ne": current_user_id },
            "read_by": { "$ne": current_user_id },
            "is_unsent": false,
        })
        .await
        .unwrap_or(0) as usize;

    let mut last_message = conv.last_message.clone();
    if let Some(ref mut lm) = last_message {
        if let Ok(Some(mdoc)) = msg_coll.find_one(doc! { "_id": &lm.id }).await {
            lm.read_count = mdoc
                .read_by
                .iter()
                .filter(|uid| *uid != &mdoc.sender_id)
                .count();
            if mdoc.is_unsent {
                lm.content = mdoc.content;
            }
        }
    }

    Ok(ConversationDto {
        id: conv.id,
        conv_type: conv.conv_type,
        name: resolved_name,
        avatar_url: resolved_avatar,
        folder,
        is_pinned,
        pinned_message: conv.pinned_message,
        unread_count,
        member_count: conv.member_ids.len().max(members.len()),
        members,
        last_message,
        created_at: conv.created_at,
        updated_at: conv.updated_at,
    })
}

pub async fn list_conversations_handler(
    auth: AuthUser,
    Query(query): Query<ListConversationsQuery>,
    State(state): State<AppState>,
) -> Result<Json<Vec<ConversationDto>>, ApiError> {
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let cursor = conv_coll
        .find(doc! { "member_ids": &auth.user_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let docs: Vec<ConversationDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let folder_filter = query
        .folder
        .unwrap_or_else(|| "all".to_string())
        .to_lowercase();

    // Batch fetch all member users in 1 query (prevent N+1)
    let mut all_member_ids: Vec<String> = docs
        .iter()
        .flat_map(|c| c.member_ids.iter().cloned())
        .collect();
    all_member_ids.sort();
    all_member_ids.dedup();

    let users_coll = state.db.collection::<UserDoc>("users");
    let user_cursor = users_coll
        .find(doc! { "_id": { "$in": &all_member_ids } })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let all_users: Vec<UserDoc> = user_cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let user_map: HashMap<String, UserDoc> =
        all_users.into_iter().map(|u| (u.id.clone(), u)).collect();

    // Batch fetch last messages in 1 query
    let last_msg_ids: Vec<String> = docs
        .iter()
        .filter_map(|c| c.last_message.as_ref().map(|lm| lm.id.clone()))
        .collect();
    let msg_coll = state.db.collection::<MessageDoc>("messages");
    let lm_cursor = msg_coll
        .find(doc! { "_id": { "$in": &last_msg_ids } })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let lm_docs: Vec<MessageDoc> = lm_cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let lm_map: HashMap<String, MessageDoc> =
        lm_docs.into_iter().map(|m| (m.id.clone(), m)).collect();

    let mut dtos = Vec::with_capacity(docs.len());
    for conv in docs {
        let member_docs: Vec<&UserDoc> = conv
            .member_ids
            .iter()
            .filter_map(|id| user_map.get(id))
            .collect();

        let members: Vec<ConversationMemberDto> = member_docs
            .iter()
            .map(|u| ConversationMemberDto {
                id: u.id.clone(),
                email: u.email.clone(),
                display_name: u.display_name.clone(),
                bc_id: u.bc_id.clone(),
                avatar_url: u.avatar_url.clone(),
                status_message: u.status_message.clone(),
                role: u.role.clone(),
                department: if u.department.is_empty() {
                    "ทั่วไป".to_string()
                } else {
                    u.department.clone()
                },
                job_title: if u.job_title.is_empty() {
                    "พนักงาน".to_string()
                } else {
                    u.job_title.clone()
                },
            })
            .collect();

        let (resolved_name, resolved_avatar) =
            if conv.conv_type == "direct" || conv.conv_type == "official" {
                if let Some(other) = member_docs.iter().find(|u| u.id != auth.user_id) {
                    (other.display_name.clone(), other.avatar_url.clone())
                } else {
                    (conv.name.clone(), conv.avatar_url.clone())
                }
            } else {
                (conv.name.clone(), conv.avatar_url.clone())
            };

        let (folder, is_pinned) = if let Some(meta) = conv.user_meta.get(&auth.user_id) {
            (meta.folder.clone(), meta.is_pinned)
        } else {
            (conv.folder.clone(), conv.is_pinned)
        };

        let unread_count = msg_coll
            .count_documents(doc! {
                "conversation_id": &conv.id,
                "sender_id": { "$ne": &auth.user_id },
                "read_by": { "$ne": &auth.user_id },
                "is_unsent": false,
            })
            .await
            .unwrap_or(0) as usize;

        let mut last_message = conv.last_message.clone();
        if let Some(ref mut lm) = last_message {
            if let Some(mdoc) = lm_map.get(&lm.id) {
                lm.read_count = mdoc
                    .read_by
                    .iter()
                    .filter(|uid| *uid != &mdoc.sender_id)
                    .count();
                if mdoc.is_unsent {
                    lm.content = mdoc.content.clone();
                }
            }
        }

        let dto = ConversationDto {
            id: conv.id,
            conv_type: conv.conv_type,
            name: resolved_name,
            avatar_url: resolved_avatar,
            folder,
            is_pinned,
            pinned_message: conv.pinned_message,
            unread_count,
            member_count: conv.member_ids.len().max(members.len()),
            members,
            last_message,
            created_at: conv.created_at,
            updated_at: conv.updated_at,
        };

        let keep = match folder_filter.as_str() {
            "all" | "" => true,
            "personal" => dto.folder == "personal",
            "work" => dto.folder == "work",
            "group" | "groups" => dto.conv_type == "group",
            "unread" => dto.unread_count > 0,
            other => dto.folder == other,
        };

        if keep {
            dtos.push(dto);
        }
    }

    dtos.sort_by(|a, b| {
        b.is_pinned
            .cmp(&a.is_pinned)
            .then_with(|| b.updated_at.cmp(&a.updated_at))
    });

    Ok(Json(dtos))
}

#[derive(Debug, Deserialize)]
pub struct CreateDirectConvRequest {
    pub friend_id: String,
}

pub async fn create_direct_conversation_handler(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<CreateDirectConvRequest>,
) -> Result<Json<ConversationDto>, ApiError> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let me = users_coll
        .find_one(doc! { "_id": &auth.user_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบข้อมูลผู้ใช้"))?;

    let friend = users_coll
        .find_one(doc! { "_id": payload.friend_id.trim() })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบข้อมูลเพื่อนที่ระบุ"))?;

    let conv = ensure_direct_conversation(
        &state,
        &me,
        &friend,
        "direct",
        "personal",
        false,
        "เริ่มการสนทนาใหม่",
    )
    .await
    .map_err(ApiError::internal)?;

    let dto = build_conversation_dto(&state, conv, &auth.user_id)
        .await
        .map_err(ApiError::internal)?;

    Ok(Json(dto))
}

#[derive(Debug, Deserialize)]
pub struct CreateGroupConvRequest {
    pub name: String,
    pub folder: Option<String>,
    pub member_ids: Vec<String>,
    pub avatar_url: Option<String>,
}

pub async fn create_group_conversation_handler(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<CreateGroupConvRequest>,
) -> Result<Json<ConversationDto>, ApiError> {
    let name = payload.name.trim().to_string();
    if name.is_empty() {
        return Err(ApiError::bad_request("กรุณาระบุชื่อกลุ่มแชท"));
    }

    let users_coll = state.db.collection::<UserDoc>("users");
    let me = users_coll
        .find_one(doc! { "_id": &auth.user_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบข้อมูลผู้ใช้"))?;

    let mut members = payload.member_ids;
    if !members.contains(&auth.user_id) {
        members.insert(0, auth.user_id.clone());
    }
    members.sort();
    members.dedup();

    let now = Utc::now().to_rfc3339();
    let conv_id = Uuid::new_v4().to_string();
    let msg_id = Uuid::new_v4().to_string();
    let sys_text = format!("{} สร้างกลุ่ม \"{}\"", me.display_name, name);

    let avatar = payload.avatar_url.unwrap_or_else(|| {
        format!(
            "https://ui-avatars.com/api/?name={}&background=06C755&color=fff&bold=true",
            urlencoding::encode(&name)
        )
    });

    let conv = ConversationDoc {
        id: conv_id.clone(),
        conv_type: "group".to_string(),
        name,
        avatar_url: avatar,
        folder: payload.folder.unwrap_or_else(|| "work".to_string()),
        is_pinned: false,
        member_ids: members,
        user_meta: HashMap::new(),
        pinned_message: None,
        last_message: Some(LastMessageSummary {
            id: msg_id.clone(),
            sender_id: me.id.clone(),
            sender_name: me.display_name.clone(),
            msg_type: "system".to_string(),
            content: sys_text.clone(),
            created_at: now.clone(),
            read_count: 0,
        }),
        created_at: now.clone(),
        updated_at: now.clone(),
    };

    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    conv_coll
        .insert_one(&conv)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let msg_coll = state.db.collection::<MessageDoc>("messages");
    let sys_msg = MessageDoc {
        id: msg_id,
        conversation_id: conv_id.clone(),
        sender_id: me.id.clone(),
        sender_name: me.display_name,
        sender_avatar: me.avatar_url,
        msg_type: "system".to_string(),
        content: sys_text,
        sticker_code: None,
        attachment: None,
        flex_payload: None,
        reply_to: None,
        read_by: vec![me.id],
        is_unsent: false,
        is_confidential: false,
        confidential_pin: None,
        expire_at: None,
        created_at: now,
    };
    let _ = msg_coll.insert_one(sys_msg).await;

    let dto = build_conversation_dto(&state, conv, &auth.user_id)
        .await
        .map_err(ApiError::internal)?;

    state.ws_hub.broadcast_event(json!({
        "event": "conversation_updated",
        "conversation_id": conv_id,
    }));

    Ok(Json(dto))
}

#[derive(Debug, Deserialize)]
pub struct UpdateConvMetaRequest {
    pub folder: Option<String>,
    pub is_pinned: Option<bool>,
    pub name: Option<String>,
}

pub async fn update_conversation_meta_handler(
    auth: AuthUser,
    Path(conv_id): Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<UpdateConvMetaRequest>,
) -> Result<Json<ConversationDto>, ApiError> {
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let mut conv = conv_coll
        .find_one(doc! { "_id": &conv_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบห้องแชท"))?;

    if let Some(folder) = payload.folder {
        conv.folder = folder.clone();
        if let Some(meta) = conv.user_meta.get_mut(&auth.user_id) {
            meta.folder = folder;
        }
    }
    if let Some(pinned) = payload.is_pinned {
        conv.is_pinned = pinned;
        if let Some(meta) = conv.user_meta.get_mut(&auth.user_id) {
            meta.is_pinned = pinned;
        }
    }
    if let Some(name) = payload.name {
        if !name.trim().is_empty() {
            conv.name = name.trim().to_string();
        }
    }

    conv_coll
        .replace_one(doc! { "_id": &conv_id }, &conv)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let dto = build_conversation_dto(&state, conv, &auth.user_id)
        .await
        .map_err(ApiError::internal)?;

    state.ws_hub.broadcast_event(json!({
        "event": "conversation_updated",
        "conversation_id": conv_id,
    }));

    Ok(Json(dto))
}

#[derive(Debug, Deserialize)]
pub struct PinMessageRequest {
    pub message_id: Option<String>,
}

pub async fn pin_message_handler(
    auth: AuthUser,
    Path(conv_id): Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<PinMessageRequest>,
) -> Result<Json<ConversationDto>, ApiError> {
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let msg_coll = state.db.collection::<MessageDoc>("messages");

    let mut conv = conv_coll
        .find_one(doc! { "_id": &conv_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบห้องแชท"))?;

    let pinned_summary = match payload.message_id {
        Some(ref mid) if !mid.trim().is_empty() => {
            let msg = msg_coll
                .find_one(doc! { "_id": mid.trim(), "conversation_id": &conv_id })
                .await
                .map_err(|e| ApiError::internal(e.to_string()))?
                .ok_or_else(|| ApiError::not_found("ไม่พบข้อความที่ต้องการปักหมุด"))?;

            Some(PinnedMessageSummary {
                id: msg.id,
                sender_id: msg.sender_id,
                sender_name: msg.sender_name,
                msg_type: msg.msg_type,
                content: msg.content,
                created_at: msg.created_at,
            })
        }
        _ => None,
    };

    conv.pinned_message = pinned_summary.clone();
    conv_coll
        .replace_one(doc! { "_id": &conv_id }, &conv)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let dto = build_conversation_dto(&state, conv, &auth.user_id)
        .await
        .map_err(ApiError::internal)?;

    state.ws_hub.broadcast_event(json!({
        "event": "conversation_updated",
        "conversation_id": conv_id,
        "pinned_message": pinned_summary,
    }));

    Ok(Json(dto))
}

pub async fn list_messages_handler(
    _auth: AuthUser,
    Path(conv_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<Vec<MessageDto>>, ApiError> {
    let msg_coll = state.db.collection::<MessageDoc>("messages");
    let files_coll = state.db.collection::<FileDoc>("files");

    let cursor = msg_coll
        .find(doc! { "conversation_id": &conv_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let docs: Vec<MessageDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let now_str = Utc::now().to_rfc3339();
    let mut active_docs = Vec::new();

    for m in docs {
        let is_expired = m
            .expire_at
            .as_ref()
            .map(|exp| !exp.is_empty() && exp.as_str() <= now_str.as_str())
            .unwrap_or(false);

        if is_expired {
            if let Some(ref att) = m.attachment {
                let _ = state.minio.delete_object(&att.key).await;
                let _ = files_coll.delete_many(doc! { "key": &att.key }).await;
            }
            let _ = msg_coll.delete_one(doc! { "_id": &m.id }).await;
        } else {
            active_docs.push(m);
        }
    }

    active_docs.sort_by(|a, b| a.created_at.cmp(&b.created_at));
    Ok(Json(active_docs.into_iter().map(MessageDto::from).collect()))
}

#[derive(Debug, Deserialize)]
pub struct SendMessageRequest {
    #[serde(rename = "type")]
    pub msg_type: Option<String>,
    pub content: Option<String>,
    pub sticker_code: Option<String>,
    pub attachment: Option<AttachmentInfo>,
    pub flex_payload: Option<Value>,
    pub reply_to_id: Option<String>,
    pub reply_to: Option<ReplyInfo>,
    #[serde(default)]
    pub is_confidential: bool,
    pub confidential_pin: Option<String>,
    pub expire_at: Option<String>,
}

pub async fn send_message_handler(
    auth: AuthUser,
    Path(conv_id): Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<SendMessageRequest>,
) -> Result<Json<MessageDto>, ApiError> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let msg_coll = state.db.collection::<MessageDoc>("messages");

    let sender = users_coll
        .find_one(doc! { "_id": &auth.user_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบข้อมูลผู้ส่ง"))?;

    let mut conv = conv_coll
        .find_one(doc! { "_id": &conv_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบห้องแชท"))?;

    let msg_type = payload
        .msg_type
        .unwrap_or_else(|| "text".to_string())
        .to_lowercase();

    let mut content = payload.content.unwrap_or_default().trim().to_string();
    if content.is_empty() {
        content = match msg_type.as_str() {
            "sticker" => "[ส่งสติ๊กเกอร์]".to_string(),
            "image" => "[ส่งรูปภาพ]".to_string(),
            "file" => payload
                .attachment
                .as_ref()
                .map(|a| format!("[ไฟล์] {}", a.file_name))
                .unwrap_or_else(|| "[ส่งไฟล์เอกสาร]".to_string()),
            "flex_card" => payload
                .flex_payload
                .as_ref()
                .and_then(|f| f.get("title").and_then(|t| t.as_str()))
                .map(|t| format!("[การ์ดบริการ] {}", t))
                .unwrap_or_else(|| "[การ์ดบริการ Mini-App]".to_string()),
            _ => "".to_string(),
        };
    }

    let mut reply_info = payload.reply_to;
    if reply_info.is_none() {
        if let Some(ref rid) = payload.reply_to_id {
            if !rid.trim().is_empty() {
                if let Ok(Some(orig)) = msg_coll.find_one(doc! { "_id": rid.trim() }).await {
                    reply_info = Some(ReplyInfo {
                        id: orig.id,
                        sender_name: orig.sender_name,
                        content: orig.content,
                    });
                }
            }
        }
    }

    let now = Utc::now().to_rfc3339();
    let msg_id = Uuid::new_v4().to_string();

    let msg_doc = MessageDoc {
        id: msg_id.clone(),
        conversation_id: conv_id.clone(),
        sender_id: sender.id.clone(),
        sender_name: sender.display_name.clone(),
        sender_avatar: sender.avatar_url.clone(),
        msg_type: msg_type.clone(),
        content: content.clone(),
        sticker_code: payload.sticker_code,
        attachment: payload.attachment,
        flex_payload: payload.flex_payload,
        reply_to: reply_info,
        read_by: vec![sender.id.clone()],
        is_unsent: false,
        is_confidential: payload.is_confidential,
        confidential_pin: payload.confidential_pin,
        expire_at: payload.expire_at,
        created_at: now.clone(),
    };

    msg_coll
        .insert_one(&msg_doc)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let preview_content = if payload.is_confidential {
        format!("🔒 [ข้อความความลับองค์กร] {}", content)
    } else {
        content
    };

    conv.last_message = Some(LastMessageSummary {
        id: msg_id,
        sender_id: sender.id,
        sender_name: sender.display_name,
        msg_type,
        content: preview_content,
        created_at: now.clone(),
        read_count: 0,
    });
    conv.updated_at = now;
    if !conv.member_ids.contains(&auth.user_id) {
        conv.member_ids.push(auth.user_id.clone());
    }

    let _ = conv_coll
        .replace_one(doc! { "_id": &conv_id }, &conv)
        .await;

    let dto = MessageDto::from(msg_doc.clone());

    state.ws_hub.broadcast_event(json!({
        "event": "new_message",
        "conversation_id": conv_id,
        "message": dto,
    }));

    // Trigger DeepSeek AI Co-Pilot if message is in 1-1 chat with AI or mentions @ai
    let _ = crate::routes::ai_routes::maybe_trigger_ai_reply(&state, &mut conv, &msg_doc).await;

    Ok(Json(dto))
}

pub async fn mark_read_handler(
    auth: AuthUser,
    Path(conv_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<Value>, ApiError> {
    let msg_coll = state.db.collection::<MessageDoc>("messages");
    let res = msg_coll
        .update_many(
            doc! {
                "conversation_id": &conv_id,
                "read_by": { "$ne": &auth.user_id }
            },
            doc! {
                "$addToSet": { "read_by": &auth.user_id }
            },
        )
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    state.ws_hub.broadcast_event(json!({
        "event": "message_read",
        "conversation_id": conv_id,
        "user_id": auth.user_id,
        "modified_count": res.modified_count,
    }));

    Ok(Json(json!({
        "status": "ok",
        "conversation_id": conv_id,
        "modified_count": res.modified_count,
    })))
}

#[derive(Debug, Deserialize)]
pub struct UnsendQuery {
    pub hard: Option<bool>,
}

pub async fn unsend_message_handler(
    auth: AuthUser,
    Path(msg_id): Path<String>,
    Query(query): Query<UnsendQuery>,
    State(state): State<AppState>,
) -> Result<Json<Value>, ApiError> {
    let hard = query.hard.unwrap_or(false);
    execute_unsend_or_purge(&auth, &msg_id, hard, &state).await
}

pub async fn purge_message_handler(
    auth: AuthUser,
    Path(msg_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<Value>, ApiError> {
    execute_unsend_or_purge(&auth, &msg_id, true, &state).await
}

async fn execute_unsend_or_purge(
    _auth: &AuthUser,
    msg_id: &str,
    hard_delete: bool,
    state: &AppState,
) -> Result<Json<Value>, ApiError> {
    let msg_coll = state.db.collection::<MessageDoc>("messages");
    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let files_coll = state.db.collection::<FileDoc>("files");

    let mut msg = msg_coll
        .find_one(doc! { "_id": msg_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบข้อความที่ต้องการยกเลิก/ลบ"))?;

    let conv_id = msg.conversation_id.clone();

    // If message had a file/image attachment in MinIO, immediately destroy it from MinIO & files collection!
    let mut file_purged = false;
    if let Some(ref att) = msg.attachment {
        let _ = state.minio.delete_object(&att.key).await;
        let _ = files_coll.delete_many(doc! { "key": &att.key }).await;
        file_purged = true;
    }

    if hard_delete {
        msg_coll
            .delete_one(doc! { "_id": msg_id })
            .await
            .map_err(|e| ApiError::internal(e.to_string()))?;

        // Refresh conversation last_message and pinned_message
        if let Ok(Some(mut conv)) = conv_coll.find_one(doc! { "_id": &conv_id }).await {
            if conv
                .pinned_message
                .as_ref()
                .map(|p| p.id == msg_id)
                .unwrap_or(false)
            {
                conv.pinned_message = None;
            }
            if conv
                .last_message
                .as_ref()
                .map(|l| l.id == msg_id)
                .unwrap_or(false)
            {
                let cursor = msg_coll
                    .find(doc! { "conversation_id": &conv_id })
                    .await
                    .map_err(|e| ApiError::internal(e.to_string()))?;
                let mut remaining: Vec<MessageDoc> = cursor
                    .try_collect()
                    .await
                    .map_err(|e| ApiError::internal(e.to_string()))?;
                remaining.sort_by(|a, b| a.created_at.cmp(&b.created_at));
                conv.last_message = remaining.pop().map(|last| {
                    let rc = last
                        .read_by
                        .iter()
                        .filter(|uid| *uid != &last.sender_id)
                        .count();
                    LastMessageSummary {
                        id: last.id,
                        sender_id: last.sender_id,
                        sender_name: last.sender_name,
                        msg_type: last.msg_type,
                        content: last.content,
                        created_at: last.created_at,
                        read_count: rc,
                    }
                });
            }
            let _ = conv_coll.replace_one(doc! { "_id": &conv_id }, &conv).await;
        }
    } else {
        let unsent_text = if file_purged {
            "ยกเลิกข้อความแล้ว (ลบไฟล์ออกจากระบบถาวรแล้ว)".to_string()
        } else {
            "ยกเลิกข้อความแล้ว".to_string()
        };

        msg.is_unsent = true;
        msg.content = unsent_text.clone();
        msg.sticker_code = None;
        msg.attachment = None;
        msg.flex_payload = None;
        msg.confidential_pin = None;

        msg_coll
            .replace_one(doc! { "_id": msg_id }, &msg)
            .await
            .map_err(|e| ApiError::internal(e.to_string()))?;

        let _ = conv_coll
            .update_one(
                doc! { "_id": &conv_id, "last_message.id": msg_id },
                doc! { "$set": { "last_message.content": &unsent_text } },
            )
            .await;
    }

    state.ws_hub.broadcast_event(json!({
        "event": "message_unsent",
        "message_id": msg_id,
        "conversation_id": conv_id,
        "hard_deleted": hard_delete,
        "file_purged": file_purged,
    }));

    Ok(Json(json!({
        "status": "ok",
        "message_id": msg_id,
        "conversation_id": conv_id,
        "hard_deleted": hard_delete,
        "file_purged": file_purged,
    })))
}

pub async fn clear_confidential_messages_handler(
    _auth: AuthUser,
    Path(conv_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<Value>, ApiError> {
    let msg_coll = state.db.collection::<MessageDoc>("messages");
    let files_coll = state.db.collection::<FileDoc>("files");

    let cursor = msg_coll
        .find(doc! { "conversation_id": &conv_id, "is_confidential": true })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let conf_msgs: Vec<MessageDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let mut purged_files = 0usize;
    for m in &conf_msgs {
        if let Some(ref att) = m.attachment {
            let _ = state.minio.delete_object(&att.key).await;
            let _ = files_coll.delete_many(doc! { "key": &att.key }).await;
            purged_files += 1;
        }
    }

    let del_res = msg_coll
        .delete_many(doc! { "conversation_id": &conv_id, "is_confidential": true })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    state.ws_hub.broadcast_event(json!({
        "event": "confidential_cleared",
        "conversation_id": conv_id,
        "purged_messages": del_res.deleted_count,
        "purged_files": purged_files,
    }));

    Ok(Json(json!({
        "status": "ok",
        "conversation_id": conv_id,
        "purged_messages": del_res.deleted_count,
        "purged_files": purged_files,
    })))
}

pub async fn conversation_vault_handler(
    _auth: AuthUser,
    Path(conv_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<VaultResponse>, ApiError> {
    let msg_coll = state.db.collection::<MessageDoc>("messages");
    let cursor = msg_coll
        .find(doc! { "conversation_id": &conv_id, "is_unsent": false })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let mut messages: Vec<MessageDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    messages.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    let mut images = Vec::new();
    let mut files = Vec::new();
    let mut links = Vec::new();

    for m in messages {
        if let Some(ref att) = m.attachment {
            let item = VaultFileItem {
                id: format!("vault_{}", m.id),
                message_id: m.id.clone(),
                sender_id: m.sender_id.clone(),
                sender_name: m.sender_name.clone(),
                key: att.key.clone(),
                url: att.url.clone(),
                file_name: att.file_name.clone(),
                mime_type: att.mime_type.clone(),
                file_size: att.file_size,
                is_confidential: m.is_confidential,
                created_at: m.created_at.clone(),
            };
            if m.msg_type == "image" || att.mime_type.starts_with("image/") {
                images.push(item);
            } else {
                files.push(item);
            }
        }

        for word in m.content.split_whitespace() {
            if word.starts_with("http://") || word.starts_with("https://") {
                let clean_url = word.trim_end_matches(|c: char| ".,);]\"".contains(c));
                links.push(VaultLinkItem {
                    id: format!("link_{}", m.id),
                    message_id: m.id.clone(),
                    sender_id: m.sender_id.clone(),
                    sender_name: m.sender_name.clone(),
                    url: clean_url.to_string(),
                    content: m.content.clone(),
                    created_at: m.created_at.clone(),
                });
            }
        }
    }

    Ok(Json(VaultResponse {
        images,
        files,
        links,
    }))
}

#[derive(Debug, Deserialize)]
pub struct SearchMessagesQuery {
    pub q: Option<String>,
    pub conversation_id: Option<String>,
}

pub async fn search_messages_handler(
    auth: AuthUser,
    Query(query): Query<SearchMessagesQuery>,
    State(state): State<AppState>,
) -> Result<Json<Vec<MessageDto>>, ApiError> {
    let q = query.q.unwrap_or_default().trim().to_string();
    if q.is_empty() {
        return Ok(Json(vec![]));
    }

    let conv_coll = state.db.collection::<ConversationDoc>("conversations");
    let msg_coll = state.db.collection::<MessageDoc>("messages");

    let allowed_conv_ids: Vec<String> = if let Some(ref cid) = query.conversation_id {
        if !cid.trim().is_empty() {
            vec![cid.trim().to_string()]
        } else {
            vec![]
        }
    } else {
        let c_cursor = conv_coll
            .find(doc! { "member_ids": &auth.user_id })
            .await
            .map_err(|e| ApiError::internal(e.to_string()))?;
        let c_docs: Vec<ConversationDoc> = c_cursor
            .try_collect()
            .await
            .map_err(|e| ApiError::internal(e.to_string()))?;
        c_docs.into_iter().map(|c| c.id).collect()
    };

    let rx = Regex {
        pattern: q,
        options: "i".to_string(),
    };

    let mut filter = doc! {
        "is_unsent": false,
        "$or": [
            { "content": rx.clone() },
            { "attachment.file_name": rx }
        ]
    };

    if !allowed_conv_ids.is_empty() {
        filter.insert("conversation_id", doc! { "$in": allowed_conv_ids });
    }

    let cursor = msg_coll
        .find(filter)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let mut docs: Vec<MessageDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    docs.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    Ok(Json(docs.into_iter().map(MessageDto::from).collect()))
}

#[derive(Debug, Deserialize)]
pub struct ListNotesQuery {
    pub conversation_id: Option<String>,
}

pub async fn list_notes_handler(
    auth: AuthUser,
    Query(query): Query<ListNotesQuery>,
    State(state): State<AppState>,
) -> Result<Json<Vec<NoteDto>>, ApiError> {
    let notes_coll = state.db.collection::<NoteDoc>("notes");

    let filter = match query.conversation_id {
        Some(ref cid) if !cid.trim().is_empty() => {
            doc! { "conversation_id": cid.trim() }
        }
        _ => {
            doc! {
                "owner_id": &auth.user_id,
                "$or": [
                    { "conversation_id": null },
                    { "conversation_id": "" }
                ]
            }
        }
    };

    let cursor = notes_coll
        .find(filter)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let mut docs: Vec<NoteDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    docs.sort_by(|a, b| {
        b.is_pinned
            .cmp(&a.is_pinned)
            .then_with(|| b.updated_at.cmp(&a.updated_at))
    });

    Ok(Json(docs.into_iter().map(NoteDto::from).collect()))
}

#[derive(Debug, Deserialize)]
pub struct CreateNoteRequest {
    pub conversation_id: Option<String>,
    pub title: String,
    pub content: String,
    #[serde(default)]
    pub attachments: Vec<AttachmentInfo>,
    #[serde(default)]
    pub is_pinned: bool,
}

pub async fn create_note_handler(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<CreateNoteRequest>,
) -> Result<Json<NoteDto>, ApiError> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let notes_coll = state.db.collection::<NoteDoc>("notes");

    let user = users_coll
        .find_one(doc! { "_id": &auth.user_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบผู้ใช้"))?;

    let conv_id = payload.conversation_id.and_then(|s| {
        if s.trim().is_empty() {
            None
        } else {
            Some(s.trim().to_string())
        }
    });

    let now = Utc::now().to_rfc3339();
    let note = NoteDoc {
        id: Uuid::new_v4().to_string(),
        conversation_id: conv_id,
        owner_id: user.id,
        owner_name: user.display_name,
        title: if payload.title.trim().is_empty() {
            "บันทึกข้อความ".to_string()
        } else {
            payload.title.trim().to_string()
        },
        content: payload.content,
        attachments: payload.attachments,
        is_pinned: payload.is_pinned,
        created_at: now.clone(),
        updated_at: now,
    };

    notes_coll
        .insert_one(&note)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    Ok(Json(NoteDto::from(note)))
}

pub async fn delete_note_handler(
    _auth: AuthUser,
    Path(note_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<Value>, ApiError> {
    let notes_coll = state.db.collection::<NoteDoc>("notes");
    notes_coll
        .delete_one(doc! { "_id": &note_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    Ok(Json(json!({
        "status": "ok",
        "id": note_id,
    })))
}
