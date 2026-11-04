pub mod auth;
pub mod config;
pub mod minio;
pub mod models;
pub mod routes;
pub mod seed;
pub mod ws;

use axum::{
    extract::DefaultBodyLimit,
    routing::{delete, get, post, put},
    Router,
};
use mongodb::{Client as MongoClient, Database};
use tower_http::cors::{Any, CorsLayer};

use crate::{
    config::AppConfig,
    minio::MinioClient,
    routes::{
        admin_routes::{
            admin_broadcast_handler, admin_create_mini_app_handler,
            admin_delete_mini_app_handler, admin_list_mini_apps_handler,
            admin_list_users_handler, admin_overview_handler, admin_update_mini_app_handler,
            admin_update_user_role_handler,
        },
        ai_routes::{
            assist_message_handler, get_ai_settings_handler, summarize_conversation_handler,
            update_ai_settings_handler,
        },
        auth_routes::{
            add_friend_handler, google_auth_handler, health_handler, list_friends_handler,
            me_handler, search_users_handler, update_profile_handler,
        },
        chat_routes::{
            clear_confidential_messages_handler, conversation_vault_handler,
            create_direct_conversation_handler, create_group_conversation_handler,
            create_note_handler, delete_note_handler, list_conversations_handler,
            list_messages_handler, list_notes_handler, mark_read_handler, pin_message_handler,
            purge_message_handler, search_messages_handler, send_message_handler,
            unsend_message_handler, update_conversation_meta_handler,
        },
        file_routes::{get_file_handler, upload_handler},
        miniapp_routes::{list_active_mini_apps_handler, serve_miniapp_html_handler},
    },
    ws::{ws_handler, WsHub},
};

#[derive(Clone)]
pub struct AppState {
    pub config: AppConfig,
    pub db: Database,
    pub minio: MinioClient,
    pub ws_hub: WsHub,
}

impl AppState {
    pub async fn init(config: AppConfig) -> Result<Self, String> {
        let mongo_client = MongoClient::with_uri_str(&config.mongodb_uri)
            .await
            .map_err(|e| format!("MongoDB connection error: {}", e))?;
        let db = mongo_client.database(&config.mongodb_db);

        let minio = MinioClient::new(
            &config.minio_endpoint,
            &config.minio_access_key,
            &config.minio_secret_key,
            &config.minio_bucket,
        );

        let ws_hub = WsHub::new();

        Ok(Self {
            config,
            db,
            minio,
            ws_hub,
        })
    }
}

pub fn create_router(state: AppState) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .route("/api/health", get(health_handler))
        // Auth & Profile
        .route("/api/auth/google", post(google_auth_handler))
        .route("/api/auth/me", get(me_handler))
        .route("/api/auth/profile", put(update_profile_handler))
        // Friends & User Search
        .route("/api/friends", get(list_friends_handler))
        .route("/api/users/search", get(search_users_handler))
        .route("/api/friends/add", post(add_friend_handler))
        // Conversations & Chat
        .route("/api/conversations", get(list_conversations_handler))
        .route(
            "/api/conversations/direct",
            post(create_direct_conversation_handler),
        )
        .route(
            "/api/conversations/group",
            post(create_group_conversation_handler),
        )
        .route(
            "/api/conversations/:id/meta",
            put(update_conversation_meta_handler),
        )
        .route(
            "/api/conversations/:id/pin-message",
            put(pin_message_handler),
        )
        .route(
            "/api/conversations/:id/messages",
            get(list_messages_handler).post(send_message_handler),
        )
        .route("/api/conversations/:id/read", post(mark_read_handler))
        .route(
            "/api/conversations/:id/clear-confidential",
            post(clear_confidential_messages_handler),
        )
        .route(
            "/api/messages/:id/unsend",
            delete(unsend_message_handler).post(unsend_message_handler),
        )
        .route(
            "/api/messages/:id/purge",
            delete(purge_message_handler).post(purge_message_handler),
        )
        .route(
            "/api/conversations/:id/vault",
            get(conversation_vault_handler),
        )
        .route("/api/messages/search", get(search_messages_handler))
        // Keep & Group Notes
        .route(
            "/api/notes",
            get(list_notes_handler).post(create_note_handler),
        )
        .route("/api/notes/:id", delete(delete_note_handler))
        // MinIO File Storage
        .route("/api/upload", post(upload_handler))
        .route("/api/files/:key", get(get_file_handler))
        // Super App Mini-Apps & Built-in Interactive WebView
        .route("/api/mini-apps", get(list_active_mini_apps_handler))
        .route("/miniapp/:code", get(serve_miniapp_html_handler))
        // DeepSeek AI Brain Endpoints
        .route("/api/ai/summarize", post(summarize_conversation_handler))
        .route("/api/ai/assist", post(assist_message_handler))
        .route(
            "/api/admin/ai-settings",
            get(get_ai_settings_handler).put(update_ai_settings_handler),
        )
        // Admin Backoffice
        .route("/api/admin/overview", get(admin_overview_handler))
        .route("/api/admin/users", get(admin_list_users_handler))
        .route(
            "/api/admin/users/:id/role",
            put(admin_update_user_role_handler),
        )
        .route(
            "/api/admin/mini-apps",
            get(admin_list_mini_apps_handler).post(admin_create_mini_app_handler),
        )
        .route(
            "/api/admin/mini-apps/:id",
            put(admin_update_mini_app_handler).delete(admin_delete_mini_app_handler),
        )
        .route("/api/admin/broadcast", post(admin_broadcast_handler))
        // WebSocket
        .route("/ws", get(ws_handler))
        .layer(DefaultBodyLimit::max(50 * 1024 * 1024))
        .layer(cors)
        .with_state(state)
}
