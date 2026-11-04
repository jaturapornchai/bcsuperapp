use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserDoc {
    #[serde(rename = "_id")]
    pub id: String,
    pub email: String,
    pub display_name: String,
    pub bc_id: String,
    pub avatar_url: String,
    pub status_message: String,
    pub qr_token: String,
    pub role: String,
    #[serde(default)]
    pub department: String,
    #[serde(default)]
    pub job_title: String,
    #[serde(default)]
    pub google_id: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserDto {
    pub id: String,
    pub email: String,
    pub display_name: String,
    pub bc_id: String,
    pub avatar_url: String,
    pub status_message: String,
    pub qr_token: String,
    pub role: String,
    pub department: String,
    pub job_title: String,
    pub created_at: String,
}

impl From<UserDoc> for UserDto {
    fn from(u: UserDoc) -> Self {
        Self {
            id: u.id,
            email: u.email,
            display_name: u.display_name,
            bc_id: u.bc_id,
            avatar_url: u.avatar_url,
            status_message: u.status_message,
            qr_token: u.qr_token,
            role: u.role,
            department: if u.department.is_empty() {
                "บริหาร".to_string()
            } else {
                u.department
            },
            job_title: if u.job_title.is_empty() {
                "พนักงานองค์กร".to_string()
            } else {
                u.job_title
            },
            created_at: u.created_at,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FriendshipDoc {
    #[serde(rename = "_id")]
    pub id: String,
    pub user_id: String,
    pub friend_id: String,
    #[serde(default)]
    pub is_favorite: bool,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FriendDto {
    pub id: String,
    pub email: String,
    pub display_name: String,
    pub bc_id: String,
    pub avatar_url: String,
    pub status_message: String,
    pub qr_token: String,
    pub role: String,
    pub department: String,
    pub job_title: String,
    pub is_favorite: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserConvMeta {
    pub folder: String,
    pub is_pinned: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PinnedMessageSummary {
    pub id: String,
    pub sender_id: String,
    pub sender_name: String,
    #[serde(rename = "type")]
    pub msg_type: String,
    pub content: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LastMessageSummary {
    pub id: String,
    pub sender_id: String,
    pub sender_name: String,
    #[serde(rename = "type")]
    pub msg_type: String,
    pub content: String,
    pub created_at: String,
    #[serde(default)]
    pub read_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationDoc {
    #[serde(rename = "_id")]
    pub id: String,
    #[serde(rename = "type")]
    pub conv_type: String, // "direct" | "group" | "official"
    pub name: String,
    pub avatar_url: String,
    pub folder: String, // "personal" | "work"
    #[serde(default)]
    pub is_pinned: bool,
    pub member_ids: Vec<String>,
    #[serde(default)]
    pub user_meta: HashMap<String, UserConvMeta>,
    #[serde(default)]
    pub pinned_message: Option<PinnedMessageSummary>,
    #[serde(default)]
    pub last_message: Option<LastMessageSummary>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationMemberDto {
    pub id: String,
    pub email: String,
    pub display_name: String,
    pub bc_id: String,
    pub avatar_url: String,
    pub status_message: String,
    pub role: String,
    pub department: String,
    pub job_title: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationDto {
    pub id: String,
    #[serde(rename = "type")]
    pub conv_type: String,
    pub name: String,
    pub avatar_url: String,
    pub folder: String,
    pub is_pinned: bool,
    pub pinned_message: Option<PinnedMessageSummary>,
    pub unread_count: usize,
    pub member_count: usize,
    pub members: Vec<ConversationMemberDto>,
    pub last_message: Option<LastMessageSummary>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttachmentInfo {
    pub key: String,
    pub url: String,
    pub file_name: String,
    pub mime_type: String,
    pub file_size: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReplyInfo {
    pub id: String,
    pub sender_name: String,
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageDoc {
    #[serde(rename = "_id")]
    pub id: String,
    pub conversation_id: String,
    pub sender_id: String,
    pub sender_name: String,
    pub sender_avatar: String,
    #[serde(rename = "type")]
    pub msg_type: String, // "text" | "sticker" | "image" | "file" | "flex_card" | "system"
    pub content: String,
    #[serde(default)]
    pub sticker_code: Option<String>,
    #[serde(default)]
    pub attachment: Option<AttachmentInfo>,
    #[serde(default)]
    pub flex_payload: Option<serde_json::Value>,
    #[serde(default)]
    pub reply_to: Option<ReplyInfo>,
    #[serde(default)]
    pub read_by: Vec<String>,
    #[serde(default)]
    pub is_unsent: bool,
    #[serde(default)]
    pub is_confidential: bool,
    #[serde(default)]
    pub confidential_pin: Option<String>,
    #[serde(default)]
    pub expire_at: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageDto {
    pub id: String,
    pub conversation_id: String,
    pub sender_id: String,
    pub sender_name: String,
    pub sender_avatar: String,
    #[serde(rename = "type")]
    pub msg_type: String,
    pub content: String,
    pub sticker_code: Option<String>,
    pub attachment: Option<AttachmentInfo>,
    pub flex_payload: Option<serde_json::Value>,
    pub reply_to: Option<ReplyInfo>,
    pub read_by: Vec<String>,
    pub read_count: usize,
    pub is_unsent: bool,
    pub is_confidential: bool,
    pub confidential_pin: Option<String>,
    pub expire_at: Option<String>,
    pub created_at: String,
}

impl From<MessageDoc> for MessageDto {
    fn from(m: MessageDoc) -> Self {
        let read_count = m
            .read_by
            .iter()
            .filter(|uid| *uid != &m.sender_id)
            .count();
        Self {
            id: m.id,
            conversation_id: m.conversation_id,
            sender_id: m.sender_id,
            sender_name: m.sender_name,
            sender_avatar: m.sender_avatar,
            msg_type: m.msg_type,
            content: m.content,
            sticker_code: m.sticker_code,
            attachment: m.attachment,
            flex_payload: m.flex_payload,
            reply_to: m.reply_to,
            read_by: m.read_by,
            read_count,
            is_unsent: m.is_unsent,
            is_confidential: m.is_confidential,
            confidential_pin: m.confidential_pin,
            expire_at: m.expire_at,
            created_at: m.created_at,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteDoc {
    #[serde(rename = "_id")]
    pub id: String,
    #[serde(default)]
    pub conversation_id: Option<String>,
    pub owner_id: String,
    pub owner_name: String,
    pub title: String,
    pub content: String,
    #[serde(default)]
    pub attachments: Vec<AttachmentInfo>,
    #[serde(default)]
    pub is_pinned: bool,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteDto {
    pub id: String,
    pub conversation_id: Option<String>,
    pub owner_id: String,
    pub owner_name: String,
    pub title: String,
    pub content: String,
    pub attachments: Vec<AttachmentInfo>,
    pub is_pinned: bool,
    pub created_at: String,
    pub updated_at: String,
}

impl From<NoteDoc> for NoteDto {
    fn from(n: NoteDoc) -> Self {
        Self {
            id: n.id,
            conversation_id: n.conversation_id,
            owner_id: n.owner_id,
            owner_name: n.owner_name,
            title: n.title,
            content: n.content,
            attachments: n.attachments,
            is_pinned: n.is_pinned,
            created_at: n.created_at,
            updated_at: n.updated_at,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileDoc {
    #[serde(rename = "_id")]
    pub id: String,
    pub key: String,
    pub url: String,
    pub file_name: String,
    pub mime_type: String,
    pub file_size: u64,
    pub uploader_id: String,
    pub uploader_name: String,
    #[serde(default)]
    pub conversation_id: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileDto {
    pub id: String,
    pub key: String,
    pub url: String,
    pub file_name: String,
    pub mime_type: String,
    pub file_size: u64,
    pub uploader_id: String,
    pub uploader_name: String,
    pub conversation_id: Option<String>,
    pub created_at: String,
}

impl From<FileDoc> for FileDto {
    fn from(f: FileDoc) -> Self {
        Self {
            id: f.id,
            key: f.key,
            url: f.url,
            file_name: f.file_name,
            mime_type: f.mime_type,
            file_size: f.file_size,
            uploader_id: f.uploader_id,
            uploader_name: f.uploader_name,
            conversation_id: f.conversation_id,
            created_at: f.created_at,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MiniAppDoc {
    #[serde(rename = "_id")]
    pub id: String,
    pub app_code: String,
    pub title: String,
    pub subtitle: String,
    pub category: String,
    pub icon_name: String,
    pub color_hex: String,
    pub entry_url: String,
    pub is_active: bool,
    pub sort_order: i32,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MiniAppDto {
    pub id: String,
    pub app_code: String,
    pub title: String,
    pub subtitle: String,
    pub category: String,
    pub icon_name: String,
    pub color_hex: String,
    pub entry_url: String,
    pub is_active: bool,
    pub sort_order: i32,
    pub created_at: String,
    pub updated_at: String,
}

impl From<MiniAppDoc> for MiniAppDto {
    fn from(m: MiniAppDoc) -> Self {
        Self {
            id: m.id,
            app_code: m.app_code,
            title: m.title,
            subtitle: m.subtitle,
            category: m.category,
            icon_name: m.icon_name,
            color_hex: m.color_hex,
            entry_url: m.entry_url,
            is_active: m.is_active,
            sort_order: m.sort_order,
            created_at: m.created_at,
            updated_at: m.updated_at,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultFileItem {
    pub id: String,
    pub message_id: String,
    pub sender_id: String,
    pub sender_name: String,
    pub key: String,
    pub url: String,
    pub file_name: String,
    pub mime_type: String,
    pub file_size: u64,
    pub is_confidential: bool,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultLinkItem {
    pub id: String,
    pub message_id: String,
    pub sender_id: String,
    pub sender_name: String,
    pub url: String,
    pub content: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultResponse {
    pub images: Vec<VaultFileItem>,
    pub files: Vec<VaultFileItem>,
    pub links: Vec<VaultLinkItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiSettingsDoc {
    #[serde(rename = "_id")]
    pub id: String,
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub api_key: String,
    pub model: String,
    pub base_url: String,
    pub system_prompt: String,
    #[serde(default)]
    pub auto_reply_in_groups: bool,
    #[serde(default)]
    pub redact_confidential: bool,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiSettingsDto {
    pub enabled: bool,
    pub has_api_key: bool,
    pub masked_key: String,
    pub model: String,
    pub base_url: String,
    pub system_prompt: String,
    pub auto_reply_in_groups: bool,
    pub redact_confidential: bool,
    pub updated_at: String,
}

pub fn mask_secret_key(raw: &str) -> (bool, String) {
    let trimmed = raw.trim();
    if trimmed.is_empty()
        || trimmed.starts_with("your-")
        || trimmed.starts_with("your_")
        || trimmed.starts_with("replace_")
    {
        return (false, "".to_string());
    }
    (true, "sk-**************** (Configured)".to_string())
}

