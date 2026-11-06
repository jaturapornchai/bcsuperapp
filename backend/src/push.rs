//! Push alerts for new chat messages through Firebase Cloud Messaging
//! (HTTP v1). Sent only to devices with no WebSocket open: a running app
//! alerts by itself (NotificationService in the frontend).

use std::{
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use bson::doc;
use futures::{StreamExt, TryStreamExt};
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::sync::Mutex;

use crate::{
    config::AppConfig,
    models::{ConversationDoc, MessageDto},
    AppState,
};

/// Sound codes the frontend ships (assets/sounds + Android res/raw/alert_<code>).
pub const SOUND_CODES: &[&str] = &[
    "ting", "pop", "chime", "marimba", "bell", "soft", "urgent", "robot", NO_SOUND,
];
pub const NO_SOUND: &str = "none";
const AI_USER_ID: &str = "user_ai";
const SCOPE: &str = "https://www.googleapis.com/auth/firebase.messaging";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AlertSounds {
    pub normal: String,
    pub urgent: String,
    pub ai: String,
}

/// One app install (device_id is made by the app), owned by the signed-in user.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceDoc {
    #[serde(rename = "_id")]
    pub id: String,
    pub user_id: String,
    pub token: String,
    pub platform: String,
    pub popup: bool,
    pub sound: bool,
    pub sounds: AlertSounds,
    pub updated_at: String,
}

#[derive(Deserialize)]
struct ServiceAccount {
    project_id: String,
    client_email: String,
    private_key: String,
    #[serde(default)]
    private_key_id: Option<String>,
    token_uri: String,
}

pub struct Fcm {
    pub project_id: String,
    client_email: String,
    key_id: Option<String>,
    key: EncodingKey,
    token_uri: String,
    api_base: String,
    http: reqwest::Client,
    access: Mutex<Option<(String, Instant)>>,
}

impl Fcm {
    /// None (push off) when FCM_SERVICE_ACCOUNT_FILE is unset or unreadable.
    pub fn from_config(config: &AppConfig) -> Option<Arc<Self>> {
        let path = config.fcm_service_account_file.trim();
        if path.is_empty() {
            tracing::info!("push off: FCM_SERVICE_ACCOUNT_FILE not set");
            return None;
        }
        let loaded = std::fs::read_to_string(path)
            .map_err(|e| e.to_string())
            .and_then(|s| serde_json::from_str::<ServiceAccount>(&s).map_err(|e| e.to_string()))
            .and_then(|sa| {
                EncodingKey::from_rsa_pem(sa.private_key.as_bytes())
                    .map(|key| (sa, key))
                    .map_err(|e| e.to_string())
            });
        match loaded {
            Ok((sa, key)) => {
                tracing::info!("push on: FCM project {}", sa.project_id);
                Some(Arc::new(Self {
                    project_id: sa.project_id,
                    client_email: sa.client_email,
                    key_id: sa.private_key_id,
                    key,
                    token_uri: sa.token_uri,
                    api_base: config.fcm_api_base.clone(),
                    http: reqwest::Client::new(),
                    access: Mutex::new(None),
                }))
            }
            Err(e) => {
                tracing::warn!("push off: cannot load FCM service account: {e}");
                None
            }
        }
    }

    /// OAuth access token from the service account, reused until near expiry.
    async fn access_token(&self) -> Result<String, String> {
        let mut cached = self.access.lock().await;
        if let Some((token, until)) = cached.as_ref() {
            if Instant::now() < *until {
                return Ok(token.clone());
            }
        }
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|e| e.to_string())?
            .as_secs();
        let claims = json!({
            "iss": self.client_email,
            "scope": SCOPE,
            "aud": self.token_uri,
            "iat": now,
            "exp": now + 3600,
        });
        let mut header = Header::new(Algorithm::RS256);
        header.kid = self.key_id.clone();
        let assertion =
            jsonwebtoken::encode(&header, &claims, &self.key).map_err(|e| e.to_string())?;
        let res: Value = self
            .http
            .post(&self.token_uri)
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", assertion.as_str()),
            ])
            .send()
            .await
            .map_err(|e| e.to_string())?
            .json()
            .await
            .map_err(|e| e.to_string())?;
        let token = res["access_token"]
            .as_str()
            .ok_or_else(|| format!("no access_token: {}", res["error"]))?
            .to_string();
        let ttl = res["expires_in"].as_u64().unwrap_or(3600).saturating_sub(300);
        *cached = Some((token.clone(), Instant::now() + Duration::from_secs(ttl)));
        Ok(token)
    }

    /// Ok(false) = FCM says the token is gone (app uninstalled / token rotated).
    /// Retries transient 429/5xx responses with bounded backoff.
    async fn send(&self, message: Value) -> Result<bool, String> {
        const RETRY_DELAYS_MS: [u64; 3] = [100, 300, 900];
        let url = format!(
            "{}/v1/projects/{}/messages:send",
            self.api_base, self.project_id
        );
        let payload = json!({ "message": message });
        let mut last_err = String::new();

        for attempt in 0..=RETRY_DELAYS_MS.len() {
            let access = self.access_token().await?;
            let res = self
                .http
                .post(&url)
                .bearer_auth(access)
                .json(&payload)
                .send()
                .await
                .map_err(|e| e.to_string())?;
            let status = res.status();
            if status.is_success() {
                return Ok(true);
            }
            let body: Value = res.json().await.unwrap_or(Value::Null);
            let unregistered = body["error"]["details"]
                .as_array()
                .is_some_and(|d| d.iter().any(|x| x["errorCode"] == "UNREGISTERED"));
            if unregistered {
                return Ok(false);
            }
            if status.as_u16() == 401 {
                *self.access.lock().await = None;
            }
            last_err = format!("FCM {status}: {}", body["error"]["message"]);
            let retryable = status.as_u16() == 429 || status.is_server_error();
            if retryable {
                if let Some(&delay_ms) = RETRY_DELAYS_MS.get(attempt) {
                    tokio::time::sleep(Duration::from_millis(delay_ms)).await;
                    continue;
                }
            }
            return Err(last_err);
        }
        Err(last_err)
    }
}

/// Title/body of the alert, or None when a message should not alert.
/// Mirrors NotificationService.describe in the frontend.
pub fn describe(conv: &ConversationDoc, msg: &MessageDto) -> Option<(String, String)> {
    if msg.msg_type == "system" || msg.is_unsent {
        return None;
    }
    let preview = if msg.is_confidential {
        "ส่งข้อความลับ 🔒".to_string()
    } else {
        match msg.msg_type.as_str() {
            "image" => "ส่งรูปภาพ".to_string(),
            "file" => match msg.attachment.as_ref().map(|a| a.file_name.trim()) {
                Some(name) if !name.is_empty() => format!("ส่งไฟล์ {name}"),
                _ => "ส่งไฟล์".to_string(),
            },
            "sticker" => "ส่งสติกเกอร์".to_string(),
            "flex_card" => "ส่งการ์ด".to_string(),
            _ => {
                let text = msg.content.trim();
                if text.chars().count() > 120 {
                    format!("{}…", text.chars().take(120).collect::<String>())
                } else {
                    text.to_string()
                }
            }
        }
    };
    let body = if msg.priority == "urgent" {
        format!("⚡ ด่วน: {preview}")
    } else {
        preview
    };
    Some(if conv.conv_type == "direct" {
        (msg.sender_name.clone(), body)
    } else {
        (conv.name.clone(), format!("{}: {body}", msg.sender_name))
    })
}

/// Sound code for this message on this device; NO_SOUND = quiet channel.
pub fn sound_for(device: &DeviceDoc, msg: &MessageDto) -> String {
    if !device.sound || msg.priority == "silent" {
        return NO_SOUND.to_string();
    }
    if msg.priority == "urgent" {
        device.sounds.urgent.clone()
    } else if msg.sender_id == AI_USER_ID {
        device.sounds.ai.clone()
    } else {
        device.sounds.normal.clone()
    }
}

/// FCM message body. Android shows it on the channel that carries the sound
/// (channels are made by the app); web gets data only and our service worker
/// shows it. One alert per room (tag), newer replaces older.
pub fn build_message(device: &DeviceDoc, conv_id: &str, title: &str, body: &str, sound: &str) -> Value {
    let mut notification = json!({
        "channel_id": format!("push_{sound}"),
        "tag": conv_id,
        "title": title,
        "body": body,
    });
    if sound != NO_SOUND {
        // Android 7 has no channels and reads the sound from here.
        notification["sound"] = json!(format!("alert_{sound}"));
    }
    let silent = if sound == NO_SOUND { "1" } else { "0" };
    json!({
        "token": device.token,
        "data": {
            "conversation_id": conv_id,
            "title": title,
            "body": body,
            "silent": silent,
        },
        "android": { "priority": "high", "notification": notification },
        "webpush": { "headers": { "Urgency": "high" } },
    })
}

/// Fire-and-forget push for a just-broadcast `new_message`.
pub fn notify_new_message(state: &AppState, conv: &ConversationDoc, msg: &MessageDto) {
    let Some(fcm) = state.push.clone() else {
        return;
    };
    let Some((title, body)) = describe(conv, msg) else {
        return;
    };
    let others: Vec<String> = conv
        .member_ids
        .iter()
        .filter(|id| **id != msg.sender_id)
        .cloned()
        .collect();
    if others.is_empty() {
        return;
    }
    let db = state.db.clone();
    let hub = state.ws_hub.clone();
    let conv_id = conv.id.clone();
    let msg = msg.clone();
    tokio::spawn(async move {
        let devices = db.collection::<DeviceDoc>("device_tokens");
        let found: Vec<DeviceDoc> = match devices
            .find(doc! { "user_id": { "$in": &others }, "popup": true })
            .await
        {
            Ok(cursor) => cursor.try_collect().await.unwrap_or_default(),
            Err(e) => {
                tracing::warn!("push: device lookup failed: {e}");
                return;
            }
        };
        let offline = found
            .into_iter()
            .filter(|d| !hub.device_online(&d.user_id, &d.id));
        // ponytail: one HTTP call per device (FCM v1 has no batch); 8 at a time.
        futures::stream::iter(offline)
            .for_each_concurrent(8, |d| {
                let fcm = fcm.clone();
                let devices = devices.clone();
                let message = build_message(&d, &conv_id, &title, &body, &sound_for(&d, &msg));
                async move {
                    match fcm.send(message).await {
                        Ok(true) => {}
                        Ok(false) => {
                            let _ = devices.delete_one(doc! { "_id": &d.id }).await;
                        }
                        Err(e) => tracing::warn!("push to device {} failed: {e}", d.id),
                    }
                }
            })
            .await;
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn conv(kind: &str) -> ConversationDoc {
        serde_json::from_value(json!({
            "_id": "c1", "type": kind, "name": "ห้องขาย", "avatar_url": "", "folder": "work",
            "member_ids": ["a", "b"], "created_at": "", "updated_at": "",
        }))
        .unwrap()
    }

    fn msg(extra: Value) -> MessageDto {
        let mut m = json!({
            "id": "m1", "conversation_id": "c1", "sender_id": "a", "sender_name": "สมชาย",
            "sender_avatar": "", "type": "text", "content": "สวัสดี", "sticker_code": null,
            "attachment": null, "flex_payload": null, "reply_to": null, "read_by": [],
            "read_count": 0, "is_unsent": false, "is_confidential": false,
            "confidential_pin": null, "expire_at": null, "priority": "normal",
            "task_status": null, "accepted_by": null, "accepted_at": null, "created_at": "",
        });
        for (k, v) in extra.as_object().unwrap() {
            m[k] = v.clone();
        }
        serde_json::from_value(m).unwrap()
    }

    fn device(sound: bool) -> DeviceDoc {
        DeviceDoc {
            id: "d1".into(),
            user_id: "b".into(),
            token: "t".into(),
            platform: "android".into(),
            popup: true,
            sound,
            sounds: AlertSounds { normal: "pop".into(), urgent: "urgent".into(), ai: "robot".into() },
            updated_at: String::new(),
        }
    }

    #[test]
    fn describe_matches_the_app_wording() {
        let direct = describe(&conv("direct"), &msg(json!({}))).unwrap();
        assert_eq!(direct, ("สมชาย".into(), "สวัสดี".into()));
        let group = describe(&conv("group"), &msg(json!({ "priority": "urgent" }))).unwrap();
        assert_eq!(group, ("ห้องขาย".into(), "สมชาย: ⚡ ด่วน: สวัสดี".into()));
        let secret = describe(&conv("direct"), &msg(json!({ "is_confidential": true }))).unwrap();
        assert_eq!(secret.1, "ส่งข้อความลับ 🔒", "confidential text must not leave the server");
        let long = describe(&conv("direct"), &msg(json!({ "content": "ก".repeat(130) }))).unwrap();
        assert_eq!(long.1.chars().count(), 121);
        assert!(describe(&conv("direct"), &msg(json!({ "type": "system" }))).is_none());
        assert!(describe(&conv("direct"), &msg(json!({ "is_unsent": true }))).is_none());
    }

    #[test]
    fn sound_follows_kind_and_switches() {
        assert_eq!(sound_for(&device(true), &msg(json!({}))), "pop");
        assert_eq!(sound_for(&device(true), &msg(json!({ "priority": "urgent" }))), "urgent");
        assert_eq!(sound_for(&device(true), &msg(json!({ "sender_id": AI_USER_ID }))), "robot");
        assert_eq!(sound_for(&device(true), &msg(json!({ "priority": "silent" }))), NO_SOUND);
        assert_eq!(sound_for(&device(false), &msg(json!({}))), NO_SOUND);
        let quiet = build_message(&device(false), "c1", "t", "b", NO_SOUND);
        assert_eq!(quiet["android"]["notification"]["channel_id"], "push_none");
        assert!(quiet["android"]["notification"].get("sound").is_none());
        assert_eq!(quiet["data"]["silent"], "1");
    }
}
