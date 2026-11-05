use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Query, State,
    },
    http::StatusCode,
    response::IntoResponse,
};
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::sync::broadcast;

use bson::doc;

use crate::{auth::verify_jwt, AppState};

#[derive(Clone)]
pub struct WsHub {
    pub tx: broadcast::Sender<String>,
    /// Open sockets per "user_id:device_id"; such devices get no push.
    online: Arc<Mutex<HashMap<String, usize>>>,
}

impl WsHub {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(1024);
        Self {
            tx,
            online: Arc::default(),
        }
    }

    pub fn device_online(&self, user_id: &str, device_id: &str) -> bool {
        let key = format!("{user_id}:{device_id}");
        self.online.lock().unwrap().contains_key(&key)
    }

    fn set_online(&self, key: &str, open: bool) {
        let mut online = self.online.lock().unwrap();
        let n = online.entry(key.to_string()).or_insert(0);
        if open {
            *n += 1;
        } else {
            *n = n.saturating_sub(1);
            if *n == 0 {
                online.remove(key);
            }
        }
    }

    pub fn broadcast_event(&self, payload: Value) {
        if let Ok(text) = serde_json::to_string(&payload) {
            let _ = self.tx.send(text);
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct WsQuery {
    pub token: Option<String>,
    /// App install id, so push skips devices that are connected.
    pub device: Option<String>,
}

pub async fn ws_handler(
    ws: WebSocketUpgrade,
    Query(query): Query<WsQuery>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let Some(user_id) = query
        .token
        .as_deref()
        .and_then(|t| verify_jwt(t, &state.config.jwt_secret).ok())
        .map(|c| c.sub)
    else {
        return StatusCode::UNAUTHORIZED.into_response();
    };

    let device_key = query
        .device
        .filter(|d| !d.is_empty() && d.len() <= 64)
        .map(|d| format!("{user_id}:{d}"));
    ws.on_upgrade(move |socket| handle_socket(socket, state, user_id, device_key))
        .into_response()
}

/// Server pings this often; a socket silent for PING_EVERY * 3 is dropped so a
/// phone that lost its network counts as offline (and gets push) soon.
const PING_EVERY: Duration = Duration::from_secs(20);

async fn handle_socket(
    socket: WebSocket,
    state: AppState,
    user_id: String,
    device_key: Option<String>,
) {
    if let Some(key) = &device_key {
        state.ws_hub.set_online(key, true);
    }
    let (mut sender, mut receiver) = socket.split();
    let mut rx = state.ws_hub.tx.subscribe();

    let welcome = json!({
        "event": "connected",
        "user_id": user_id,
    });
    if let Ok(text) = serde_json::to_string(&welcome) {
        let _ = sender.send(Message::Text(text.into())).await;
    }

    let send_state = state.clone();
    let send_uid = user_id.clone();
    let mut send_task = tokio::spawn(async move {
        let mut ping = tokio::time::interval(PING_EVERY);
        loop {
            let out = tokio::select! {
                _ = ping.tick() => Message::Ping(Vec::new().into()),
                msg = rx.recv() => match msg {
                    Ok(msg) if can_receive(&send_state, &send_uid, &msg).await => {
                        Message::Text(msg.into())
                    }
                    Ok(_) | Err(broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(broadcast::error::RecvError::Closed) => break,
                },
            };
            if sender.send(out).await.is_err() {
                break;
            }
        }
    });

    let ws_hub = state.ws_hub.clone();
    let uid = user_id.clone();
    let mut recv_task = tokio::spawn(async move {
        // Any frame (pong included) proves the client is still there.
        while let Ok(Some(Ok(msg))) =
            tokio::time::timeout(PING_EVERY * 3, receiver.next()).await
        {
            if let Message::Text(text) = msg {
                if let Ok(val) = serde_json::from_str::<Value>(&text) {
                    if val.get("event").and_then(|v| v.as_str()) == Some("typing") {
                        ws_hub.broadcast_event(json!({
                            "event": "typing",
                            "user_id": uid,
                            "conversation_id": val.get("conversation_id"),
                        }));
                    }
                }
            } else if let Message::Close(_) = msg {
                break;
            }
        }
    });

    tokio::select! {
        _ = (&mut send_task) => recv_task.abort(),
        _ = (&mut recv_task) => send_task.abort(),
    };
    if let Some(key) = &device_key {
        state.ws_hub.set_online(key, false);
    }
}

/// Room events (anything with conversation_id) go only to that room's members;
/// org-wide events (theme, mini-apps) go to everyone.
// ponytail: one indexed count per room event per socket; cache memberships per socket if traffic grows.
async fn can_receive(state: &AppState, user_id: &str, raw: &str) -> bool {
    let conv_id = serde_json::from_str::<Value>(raw).ok().and_then(|v| {
        v.get("conversation_id")
            .and_then(|c| c.as_str())
            .map(str::to_owned)
    });
    let Some(conv_id) = conv_id else {
        return true;
    };
    state
        .db
        .collection::<bson::Document>("conversations")
        .count_documents(doc! { "_id": &conv_id, "member_ids": user_id })
        .await
        .map(|n| n > 0)
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::WsHub;

    #[test]
    fn device_counts_as_online_until_its_last_socket_closes() {
        let hub = WsHub::new();
        hub.set_online("u1:d1", true);
        hub.set_online("u1:d1", true);
        hub.set_online("u1:d1", false);
        assert!(hub.device_online("u1", "d1"));
        assert!(!hub.device_online("u2", "d1"), "another user's socket must not count");
        hub.set_online("u1:d1", false);
        assert!(!hub.device_online("u1", "d1"));
    }
}
