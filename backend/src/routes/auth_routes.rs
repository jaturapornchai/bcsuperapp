use axum::{
    extract::{Query, State},
    Json,
};
use bson::{doc, Regex};
use chrono::Utc;
use futures_util::TryStreamExt;
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{
    auth::{create_jwt, ApiError, AuthUser},
    models::{FriendDto, FriendshipDoc, UserDoc, UserDto},
    routes::chat_routes::build_conversation_dto,
    seed::{ensure_direct_conversation, ensure_friendship_pair, ensure_user_onboarding},
    AppState,
};

pub async fn health_handler(State(state): State<AppState>) -> Json<Value> {
    let mongo_ok = state
        .db
        .run_command(doc! { "ping": 1 })
        .await
        .is_ok();
    let minio_ok = state.minio.check_health().await;

    Json(json!({
        "status": "ok",
        "mongodb": mongo_ok,
        "minio": minio_ok,
    }))
}

#[derive(Debug, Deserialize)]
pub struct GoogleAuthRequest {
    pub email: Option<String>,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub google_id: Option<String>,
    pub id_token: Option<String>,
    pub department: Option<String>,
    pub job_title: Option<String>,
}

pub async fn google_auth_handler(
    State(state): State<AppState>,
    Json(payload): Json<GoogleAuthRequest>,
) -> Result<Json<Value>, ApiError> {
    let mut email = payload
        .email
        .unwrap_or_default()
        .trim()
        .to_lowercase();
    let mut display_name = payload
        .display_name
        .unwrap_or_default()
        .trim()
        .to_string();
    let mut avatar_url = payload
        .avatar_url
        .unwrap_or_default()
        .trim()
        .to_string();
    let mut google_id = payload.google_id.clone();

    if let Some(ref id_tok) = payload.id_token {
        if !id_tok.trim().is_empty() && !id_tok.starts_with("demo_") {
            let verify_url = format!(
                "https://oauth2.googleapis.com/tokeninfo?id_token={}",
                urlencoding::encode(id_tok.trim())
            );
            if let Ok(resp) = state.minio.http.get(&verify_url).send().await {
                if resp.status().is_success() {
                    if let Ok(info) = resp.json::<Value>().await {
                        if let Some(em) = info.get("email").and_then(|v| v.as_str()) {
                            email = em.to_lowercase();
                        }
                        if display_name.is_empty() {
                            if let Some(nm) = info.get("name").and_then(|v| v.as_str()) {
                                display_name = nm.to_string();
                            }
                        }
                        if avatar_url.is_empty() {
                            if let Some(pic) = info.get("picture").and_then(|v| v.as_str()) {
                                avatar_url = pic.to_string();
                            }
                        }
                        if google_id.is_none() {
                            if let Some(sub) = info.get("sub").and_then(|v| v.as_str()) {
                                google_id = Some(sub.to_string());
                            }
                        }
                    }
                }
            }
        }
    }

    if email.is_empty() {
        return Err(ApiError::bad_request("กรุณาระบุอีเมล Gmail สำหรับเข้าสู่ระบบ"));
    }

    let users_coll = state.db.collection::<UserDoc>("users");
    let existing = users_coll
        .find_one(doc! { "email": &email })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let user = if let Some(mut u) = existing {
        let mut updated = false;
        if !display_name.is_empty() && u.display_name != display_name {
            u.display_name = display_name;
            updated = true;
        }
        if !avatar_url.is_empty() && u.avatar_url != avatar_url {
            u.avatar_url = avatar_url;
            updated = true;
        }
        if let Some(dept) = payload.department {
            if !dept.trim().is_empty() && u.department != dept.trim() {
                u.department = dept.trim().to_string();
                updated = true;
            }
        }
        if let Some(title) = payload.job_title {
            if !title.trim().is_empty() && u.job_title != title.trim() {
                u.job_title = title.trim().to_string();
                updated = true;
            }
        }
        if updated {
            let _ = users_coll
                .update_one(
                    doc! { "_id": &u.id },
                    doc! {
                        "$set": {
                            "display_name": &u.display_name,
                            "avatar_url": &u.avatar_url,
                            "department": &u.department,
                            "job_title": &u.job_title,
                        }
                    },
                )
                .await;
        }
        u
    } else {
        let local_part = email
            .split('@')
            .next()
            .unwrap_or("user")
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || *c == '.' || *c == '_')
            .collect::<String>();

        let default_name = if display_name.is_empty() {
            local_part.clone()
        } else {
            display_name
        };

        let default_avatar = if avatar_url.is_empty() {
            format!(
                "https://ui-avatars.com/api/?name={}&background=06C755&color=fff&bold=true",
                urlencoding::encode(&default_name)
            )
        } else {
            avatar_url
        };

        let bc_id = format!("{}.bc", local_part);
        let qr_token = format!("BCQR_{}", Uuid::new_v4().simple());

        let new_user = UserDoc {
            id: format!("user_{}", Uuid::new_v4().simple()),
            email: email.clone(),
            display_name: default_name,
            bc_id,
            avatar_url: default_avatar,
            status_message: "ใช้งาน BC Super App (Enterprise Security)".to_string(),
            qr_token,
            // New sign-ups are regular staff; an admin promotes them in the backoffice.
            role: "user".to_string(),
            department: payload.department.unwrap_or_else(|| "ทั่วไป".to_string()),
            job_title: payload
                .job_title
                .unwrap_or_else(|| "พนักงาน".to_string()),
            google_id,
            created_at: Utc::now().to_rfc3339(),
        };

        users_coll
            .insert_one(&new_user)
            .await
            .map_err(|e| ApiError::internal(e.to_string()))?;

        new_user
    };

    let _ = ensure_user_onboarding(&state, &user).await;

    let token = create_jwt(&user.id, &user.email, &user.role, &state.config.jwt_secret)
        .map_err(ApiError::internal)?;

    let dto = UserDto::from(user);
    Ok(Json(json!({
        "token": token,
        "user": dto,
    })))
}

pub async fn me_handler(
    auth: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, ApiError> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let user = users_coll
        .find_one(doc! { "_id": &auth.user_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบข้อมูลผู้ใช้"))?;

    let dto = UserDto::from(user);
    let mut val = serde_json::to_value(&dto).unwrap_or_else(|_| json!({}));
    if let Some(obj) = val.as_object_mut() {
        obj.insert("user".to_string(), serde_json::to_value(&dto).unwrap_or_default());
    }
    Ok(Json(val))
}

#[derive(Debug, Deserialize)]
pub struct UpdateProfileRequest {
    pub display_name: Option<String>,
    pub bc_id: Option<String>,
    pub status_message: Option<String>,
    pub avatar_url: Option<String>,
    pub role: Option<String>,
    pub department: Option<String>,
    pub job_title: Option<String>,
}

pub async fn update_profile_handler(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<UpdateProfileRequest>,
) -> Result<Json<Value>, ApiError> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let mut user = users_coll
        .find_one(doc! { "_id": &auth.user_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบข้อมูลผู้ใช้"))?;

    if let Some(name) = payload.display_name {
        if !name.trim().is_empty() {
            user.display_name = name.trim().to_string();
        }
    }
    if let Some(bc_id) = payload.bc_id {
        if !bc_id.trim().is_empty() {
            user.bc_id = bc_id.trim().to_string();
        }
    }
    if let Some(status) = payload.status_message {
        user.status_message = status.trim().to_string();
    }
    if let Some(avatar) = payload.avatar_url {
        if !avatar.trim().is_empty() {
            user.avatar_url = avatar.trim().to_string();
        }
    }
    if let Some(role) = payload.role {
        if role == "admin" || role == "user" {
            user.role = role;
        }
    }
    if let Some(dept) = payload.department {
        if !dept.trim().is_empty() {
            user.department = dept.trim().to_string();
        }
    }
    if let Some(title) = payload.job_title {
        if !title.trim().is_empty() {
            user.job_title = title.trim().to_string();
        }
    }

    users_coll
        .update_one(
            doc! { "_id": &user.id },
            doc! {
                "$set": {
                    "display_name": &user.display_name,
                    "bc_id": &user.bc_id,
                    "status_message": &user.status_message,
                    "avatar_url": &user.avatar_url,
                    "role": &user.role,
                    "department": &user.department,
                    "job_title": &user.job_title,
                }
            },
        )
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let dto = UserDto::from(user);
    let mut val = serde_json::to_value(&dto).unwrap_or_else(|_| json!({}));
    if let Some(obj) = val.as_object_mut() {
        obj.insert("user".to_string(), serde_json::to_value(&dto).unwrap_or_default());
    }
    Ok(Json(val))
}

pub async fn list_friends_handler(
    auth: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Vec<FriendDto>>, ApiError> {
    let friends_coll = state.db.collection::<FriendshipDoc>("friendships");
    let users_coll = state.db.collection::<UserDoc>("users");

    let cursor = friends_coll
        .find(doc! { "user_id": &auth.user_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let friendships: Vec<FriendshipDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    let mut result = Vec::new();
    for f in friendships {
        if let Some(u) = users_coll
            .find_one(doc! { "_id": &f.friend_id })
            .await
            .map_err(|e| ApiError::internal(e.to_string()))?
        {
            result.push(FriendDto {
                id: u.id,
                email: u.email,
                display_name: u.display_name,
                bc_id: u.bc_id,
                avatar_url: u.avatar_url,
                status_message: u.status_message,
                qr_token: u.qr_token,
                role: u.role,
                department: if u.department.is_empty() {
                    "ทั่วไป".to_string()
                } else {
                    u.department
                },
                job_title: if u.job_title.is_empty() {
                    "พนักงาน".to_string()
                } else {
                    u.job_title
                },
                is_favorite: f.is_favorite,
            });
        }
    }

    result.sort_by(|a, b| {
        b.is_favorite
            .cmp(&a.is_favorite)
            .then_with(|| a.display_name.cmp(&b.display_name))
    });

    Ok(Json(result))
}

#[derive(Debug, Deserialize)]
pub struct SearchUserQuery {
    pub q: Option<String>,
}

pub async fn search_users_handler(
    _auth: AuthUser,
    Query(query): Query<SearchUserQuery>,
    State(state): State<AppState>,
) -> Result<Json<Vec<UserDto>>, ApiError> {
    let q = query.q.unwrap_or_default().trim().to_string();
    let users_coll = state.db.collection::<UserDoc>("users");

    let filter = if q.is_empty() {
        doc! {}
    } else {
        let escaped = regex_escape(&q);
        let rx = Regex {
            pattern: escaped,
            options: "i".to_string(),
        };
        doc! {
            "$or": [
                { "bc_id": rx.clone() },
                { "email": rx.clone() },
                { "qr_token": rx.clone() },
                { "display_name": rx.clone() },
                { "department": rx }
            ]
        }
    };

    let cursor = users_coll
        .find(filter)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let docs: Vec<UserDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    Ok(Json(docs.into_iter().map(UserDto::from).collect()))
}

fn regex_escape(s: &str) -> String {
    let mut out = String::new();
    for c in s.chars() {
        if "\\.^$|?*+()[]{}".contains(c) {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

#[derive(Debug, Deserialize)]
pub struct AddFriendRequest {
    pub target_id: Option<String>,
    pub bc_id: Option<String>,
    pub email: Option<String>,
    pub qr_token: Option<String>,
}

pub async fn add_friend_handler(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<AddFriendRequest>,
) -> Result<Json<Value>, ApiError> {
    let users_coll = state.db.collection::<UserDoc>("users");
    let me = users_coll
        .find_one(doc! { "_id": &auth.user_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .ok_or_else(|| ApiError::not_found("ไม่พบผู้ใช้ปัจจุบัน"))?;

    let mut target: Option<UserDoc> = None;

    if let Some(ref tid) = payload.target_id {
        if !tid.trim().is_empty() {
            target = users_coll
                .find_one(doc! { "_id": tid.trim() })
                .await
                .map_err(|e| ApiError::internal(e.to_string()))?;
        }
    }
    if target.is_none() {
        if let Some(ref bid) = payload.bc_id {
            if !bid.trim().is_empty() {
                target = users_coll
                    .find_one(doc! { "bc_id": bid.trim() })
                    .await
                    .map_err(|e| ApiError::internal(e.to_string()))?;
            }
        }
    }
    if target.is_none() {
        if let Some(ref em) = payload.email {
            if !em.trim().is_empty() {
                target = users_coll
                    .find_one(doc! { "email": em.trim().to_lowercase() })
                    .await
                    .map_err(|e| ApiError::internal(e.to_string()))?;
            }
        }
    }
    if target.is_none() {
        if let Some(ref qr) = payload.qr_token {
            if !qr.trim().is_empty() {
                target = users_coll
                    .find_one(doc! { "qr_token": qr.trim() })
                    .await
                    .map_err(|e| ApiError::internal(e.to_string()))?;
            }
        }
    }

    let partner = target.ok_or_else(|| {
        ApiError::not_found("ไม่พบผู้ใช้จาก BC ID / Gmail / QR Code ที่ระบุ")
    })?;

    if partner.id == me.id {
        return Err(ApiError::bad_request("ไม่สามารถเพิ่มตัวเองเป็นเพื่อนได้"));
    }

    ensure_friendship_pair(&state, &me.id, &partner.id, false)
        .await
        .map_err(ApiError::internal)?;

    let conv = ensure_direct_conversation(
        &state,
        &me,
        &partner,
        "direct",
        "personal",
        false,
        "เราเป็นเพื่อนกันบน BC Super App แล้ว ทักทายกันได้เลย!",
    )
    .await
    .map_err(ApiError::internal)?;

    let conv_dto = build_conversation_dto(&state, conv, &me.id)
        .await
        .map_err(ApiError::internal)?;

    let friend_dto = FriendDto {
        id: partner.id,
        email: partner.email,
        display_name: partner.display_name,
        bc_id: partner.bc_id,
        avatar_url: partner.avatar_url,
        status_message: partner.status_message,
        qr_token: partner.qr_token,
        role: partner.role,
        department: if partner.department.is_empty() {
            "ทั่วไป".to_string()
        } else {
            partner.department
        },
        job_title: if partner.job_title.is_empty() {
            "พนักงาน".to_string()
        } else {
            partner.job_title
        },
        is_favorite: false,
    };

    Ok(Json(json!({
        "friend": friend_dto,
        "conversation_id": conv_dto.id,
        "conversation": conv_dto,
    })))
}
