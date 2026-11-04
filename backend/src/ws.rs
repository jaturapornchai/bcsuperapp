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
use tokio::sync::broadcast;

use bson::doc;

use crate::{auth::verify_jwt, AppState};

#[derive(Clone)]
pub struct WsHub {
    pub tx: broadcast::Sender<String>,
}

impl WsHub {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(1024);
        Self { tx }
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

    ws.on_upgrade(move |socket| handle_socket(socket, state, user_id))
        .into_response()
}

async fn handle_socket(socket: WebSocket, state: AppState, user_id: String) {
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
        while let Ok(msg) = rx.recv().await {
            if !can_receive(&send_state, &send_uid, &msg).await {
                continue;
            }
            if sender.send(Message::Text(msg.into())).await.is_err() {
                break;
            }
        }
    });

    let ws_hub = state.ws_hub.clone();
    let uid = user_id.clone();
    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
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
