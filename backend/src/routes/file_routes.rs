use axum::{
    body::Body,
    extract::{FromRequest, Multipart, Path, Request, State},
    http::{header, StatusCode},
    response::Response,
    Json,
};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use bson::doc;
use chrono::Utc;
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{
    auth::{ApiError, AuthUser},
    minio::MinioClient,
    models::{FileDoc, UserDoc},
    AppState,
};

#[derive(Debug, Deserialize)]
pub struct UploadBase64Request {
    pub file_name: String,
    pub mime_type: Option<String>,
    pub data_base64: String,
    pub conversation_id: Option<String>,
}

pub async fn upload_handler(
    auth: AuthUser,
    State(state): State<AppState>,
    req: Request,
) -> Result<Json<Value>, ApiError> {
    let content_type = req
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_lowercase();

    let mut file_name = "uploaded_file.bin".to_string();
    let mut mime_type = "application/octet-stream".to_string();
    let mut conversation_id: Option<String> = None;
    let mut file_bytes: Vec<u8> = Vec::new();

    if content_type.starts_with("multipart/form-data") {
        let mut multipart = Multipart::from_request(req, &state)
            .await
            .map_err(|e| ApiError::bad_request(format!("Multipart error: {}", e)))?;

        while let Some(field) = multipart
            .next_field()
            .await
            .map_err(|e| ApiError::bad_request(format!("Field error: {}", e)))?
        {
            let field_name = field.name().unwrap_or("").to_string();
            if field_name == "conversation_id" {
                if let Ok(txt) = field.text().await {
                    if !txt.trim().is_empty() {
                        conversation_id = Some(txt.trim().to_string());
                    }
                }
            } else if field_name == "file_name" {
                if let Ok(txt) = field.text().await {
                    if !txt.trim().is_empty() {
                        file_name = txt.trim().to_string();
                    }
                }
            } else if field_name == "mime_type" {
                if let Ok(txt) = field.text().await {
                    if !txt.trim().is_empty() {
                        mime_type = txt.trim().to_string();
                    }
                }
            } else {
                if let Some(fname) = field.file_name() {
                    if !fname.is_empty() {
                        file_name = fname.to_string();
                    }
                }
                if let Some(ct) = field.content_type() {
                    if !ct.is_empty() {
                        mime_type = ct.to_string();
                    }
                }
                let data = field
                    .bytes()
                    .await
                    .map_err(|e| ApiError::bad_request(format!("Read bytes error: {}", e)))?;
                file_bytes = data.to_vec();
            }
        }
    } else {
        let body_bytes = axum::body::to_bytes(req.into_body(), 50 * 1024 * 1024)
            .await
            .map_err(|e| ApiError::bad_request(format!("Body read error: {}", e)))?;
        let payload: UploadBase64Request = serde_json::from_slice(&body_bytes)
            .map_err(|e| ApiError::bad_request(format!("Invalid JSON upload payload: {}", e)))?;

        if !payload.file_name.trim().is_empty() {
            file_name = payload.file_name.trim().to_string();
        }
        if let Some(mt) = payload.mime_type {
            if !mt.trim().is_empty() {
                mime_type = mt.trim().to_string();
            }
        } else {
            mime_type = guess_mime(&file_name);
        }
        conversation_id = payload.conversation_id;

        let raw_b64 = payload
            .data_base64
            .split_once(";base64,")
            .map(|(_, b)| b)
            .unwrap_or(payload.data_base64.as_str())
            .trim();

        file_bytes = BASE64
            .decode(raw_b64)
            .map_err(|e| ApiError::bad_request(format!("Base64 decode error: {}", e)))?;
    }

    if file_bytes.is_empty() {
        return Err(ApiError::bad_request("ไม่พบข้อมูลไฟล์ที่อัปโหลด"));
    }

    if mime_type == "application/octet-stream" {
        mime_type = guess_mime(&file_name);
    }

    let safe_name = MinioClient::sanitize_key(&file_name);
    let key = format!(
        "{}_{}_{}",
        Utc::now().timestamp(),
        &Uuid::new_v4().simple().to_string()[..8],
        safe_name
    );

    state
        .minio
        .put_object(&key, &file_bytes, &mime_type)
        .await
        .map_err(ApiError::internal)?;

    let url = format!("{}/api/files/{}", state.config.public_base_url, key);
    let file_size = file_bytes.len() as u64;

    let users_coll = state.db.collection::<UserDoc>("users");
    let uploader_name = users_coll
        .find_one(doc! { "_id": &auth.user_id })
        .await
        .ok()
        .flatten()
        .map(|u| u.display_name)
        .unwrap_or_else(|| auth.email.clone());

    let file_doc = FileDoc {
        id: Uuid::new_v4().to_string(),
        key: key.clone(),
        url: url.clone(),
        file_name: file_name.clone(),
        mime_type: mime_type.clone(),
        file_size,
        uploader_id: auth.user_id,
        uploader_name,
        conversation_id,
        created_at: Utc::now().to_rfc3339(),
    };

    let files_coll = state.db.collection::<FileDoc>("files");
    let _ = files_coll.insert_one(&file_doc).await;

    Ok(Json(json!({
        "id": file_doc.id,
        "key": key,
        "url": url,
        "file_name": file_name,
        "mime_type": mime_type,
        "file_size": file_size,
    })))
}

pub async fn get_file_handler(
    Path(key): Path<String>,
    State(state): State<AppState>,
) -> Result<Response, ApiError> {
    let files_coll = state.db.collection::<FileDoc>("files");
    let meta_opt = files_coll
        .find_one(doc! { "key": &key })
        .await
        .ok()
        .flatten();

    let (bytes, minio_ct) = state
        .minio
        .get_object(&key)
        .await
        .map_err(|_| ApiError::not_found("ไม่พบไฟล์ในระบบจัดเก็บถาวร MinIO"))?;

    let content_type = meta_opt
        .as_ref()
        .map(|m| m.mime_type.clone())
        .unwrap_or_else(|| {
            if minio_ct == "application/octet-stream" {
                guess_mime(&key)
            } else {
                minio_ct
            }
        });

    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .header(
            header::CACHE_CONTROL,
            "public, max-age=31536000, immutable",
        )
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .body(Body::from(bytes))
        .map_err(|e| ApiError::internal(e.to_string()))
}

fn guess_mime(filename: &str) -> String {
    let lower = filename.to_lowercase();
    if lower.ends_with(".png") {
        "image/png".to_string()
    } else if lower.ends_with(".jpg") || lower.ends_with(".jpeg") {
        "image/jpeg".to_string()
    } else if lower.ends_with(".gif") {
        "image/gif".to_string()
    } else if lower.ends_with(".webp") {
        "image/webp".to_string()
    } else if lower.ends_with(".svg") {
        "image/svg+xml".to_string()
    } else if lower.ends_with(".pdf") {
        "application/pdf".to_string()
    } else if lower.ends_with(".txt") || lower.ends_with(".csv") {
        "text/plain; charset=utf-8".to_string()
    } else if lower.ends_with(".json") {
        "application/json".to_string()
    } else {
        "application/octet-stream".to_string()
    }
}
