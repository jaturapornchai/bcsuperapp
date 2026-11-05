use axum::{
    extract::{Path, State},
    Json,
};
use bson::doc;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::{
    auth::{ApiError, AuthUser},
    push::{AlertSounds, DeviceDoc, SOUND_CODES},
    AppState,
};

#[derive(Deserialize)]
pub struct RegisterDeviceRequest {
    pub device_id: String,
    pub token: String,
    pub platform: String,
    pub popup: bool,
    pub sound: bool,
    pub sounds: AlertSounds,
}

fn validate(req: &RegisterDeviceRequest) -> Result<(), ApiError> {
    let id_ok = (8..=64).contains(&req.device_id.len())
        && req.device_id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-');
    let token_ok = (1..=4096).contains(&req.token.len())
        && !req.token.chars().any(char::is_whitespace);
    let sounds_ok = [&req.sounds.normal, &req.sounds.urgent, &req.sounds.ai]
        .iter()
        .all(|s| SOUND_CODES.contains(&s.as_str()));
    if !id_ok || !token_ok {
        return Err(ApiError::bad_request("device_id หรือ token ไม่ถูกต้อง"));
    }
    if !matches!(req.platform.as_str(), "android" | "web") {
        return Err(ApiError::bad_request("platform ต้องเป็น android หรือ web"));
    }
    if !sounds_ok {
        return Err(ApiError::bad_request("รหัสเสียงไม่ถูกต้อง"));
    }
    Ok(())
}

/// Saves this install's push token and alert settings for the signed-in user.
/// The last account signed in on a device owns it.
pub async fn register_device_handler(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(req): Json<RegisterDeviceRequest>,
) -> Result<Json<Value>, ApiError> {
    validate(&req)?;
    let coll = state.db.collection::<DeviceDoc>("device_tokens");
    let device = DeviceDoc {
        id: req.device_id,
        user_id: auth.user_id,
        token: req.token,
        platform: req.platform,
        popup: req.popup,
        sound: req.sound,
        sounds: req.sounds,
        updated_at: chrono::Utc::now().to_rfc3339(),
    };
    // Same token under an old device id would alert twice.
    coll.delete_many(doc! { "token": &device.token, "_id": { "$ne": &device.id } })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    coll.replace_one(doc! { "_id": &device.id }, &device)
        .upsert(true)
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    Ok(Json(json!({ "status": "ok", "push": state.push.is_some() })))
}

/// Stops push to this device (called on sign-out).
pub async fn unregister_device_handler(
    auth: AuthUser,
    State(state): State<AppState>,
    Path(device_id): Path<String>,
) -> Result<Json<Value>, ApiError> {
    state
        .db
        .collection::<DeviceDoc>("device_tokens")
        .delete_one(doc! { "_id": &device_id, "user_id": &auth.user_id })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    Ok(Json(json!({ "status": "ok" })))
}

/// Firebase web config for browsers (public values, kept in .env so they are
/// not in git). `web` is null until push and all FCM_WEB_* are set.
pub async fn push_config_handler(
    _auth: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, ApiError> {
    let c = &state.config;
    let web = state.push.as_ref().and_then(|fcm| {
        let parts = [
            &c.fcm_web_api_key,
            &c.fcm_web_app_id,
            &c.fcm_web_sender_id,
            &c.fcm_web_vapid_key,
        ];
        parts.iter().all(|p| !p.is_empty()).then(|| {
            json!({
                "apiKey": c.fcm_web_api_key,
                "appId": c.fcm_web_app_id,
                "messagingSenderId": c.fcm_web_sender_id,
                "projectId": fcm.project_id,
                "vapidKey": c.fcm_web_vapid_key,
            })
        })
    });
    Ok(Json(json!({ "enabled": state.push.is_some(), "web": web })))
}
