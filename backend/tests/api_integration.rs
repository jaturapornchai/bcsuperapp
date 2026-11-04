use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use bcapp_backend::{config::AppConfig, create_router, seed::seed_initial_data, AppState};
use serde_json::{json, Value};
use tower::ServiceExt;

#[tokio::test]
async fn test_full_bcapp_api_and_minio_mongo_flow() {
    let config = AppConfig::from_env();
    let state = AppState::init(config).await.expect("init AppState");
    seed_initial_data(&state).await.expect("seed initial data");

    let app = create_router(state);

    // 1. Health check
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let health: Value = serde_json::from_slice(&body_bytes).unwrap();
    assert_eq!(health["status"], "ok");
    assert_eq!(health["mongodb"], true);
    assert_eq!(health["minio"], true);

    // 2. Google Login
    let login_req = json!({
        "email": "jead@bcapp.local",
        "display_name": "ลุงจืด (Super Admin)"
    });
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/auth/google")
                .header("content-type", "application/json")
                .body(Body::from(login_req.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let auth_json: Value = serde_json::from_slice(&body_bytes).unwrap();
    let token = auth_json["token"].as_str().expect("jwt token").to_string();
    assert_eq!(auth_json["user"]["role"], "admin");

    // 3. Conversations list
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/conversations?folder=all")
                .header("authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let convs: Value = serde_json::from_slice(&body_bytes).unwrap();
    assert!(!convs.as_array().unwrap().is_empty());

    // 4. Upload file to MinIO and fetch back
    let sample_content = b"BC Super App Permanent File Vault Verification 100%";
    let upload_req = json!({
        "file_name": "verify_vault.txt",
        "mime_type": "text/plain",
        "data_base64": BASE64.encode(sample_content),
        "conversation_id": "conv_group_office"
    });
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/upload")
                .header("authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(upload_req.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let uploaded: Value = serde_json::from_slice(&body_bytes).unwrap();
    let file_key = uploaded["key"].as_str().unwrap();

    // Fetch file from /api/files/:key
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{}", file_key))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let downloaded_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    assert_eq!(downloaded_bytes.as_ref(), sample_content);

    // 5. Send message & check vault
    let send_msg_req = json!({
        "type": "text",
        "content": "ทดสอบส่งข้อความพร้อมลิงก์ https://smlwork.com"
    });
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/conversations/conv_group_office/messages")
                .header("authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(send_msg_req.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);

    // 6. Check Vault
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/conversations/conv_group_office/vault")
                .header("authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let vault: Value = serde_json::from_slice(&body_bytes).unwrap();
    assert!(!vault["images"].as_array().unwrap().is_empty());
    assert!(!vault["files"].as_array().unwrap().is_empty());
    assert!(!vault["links"].as_array().unwrap().is_empty());

    // 7. Admin overview & Mini-apps
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/admin/overview")
                .header("authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let overview: Value = serde_json::from_slice(&body_bytes).unwrap();
    assert!(overview["total_users"].as_u64().unwrap() >= 4);
    assert!(overview["total_mini_apps"].as_u64().unwrap() >= 4);

    // 8. Test Confidential File Message & Instant Purge (destroys file in MinIO + removes message)
    let secret_bytes = b"TOP SECRET ENTERPRISE CONTRACT - ACCIDENTAL SEND";
    let secret_upload_req = json!({
        "file_name": "secret_contract.txt",
        "mime_type": "text/plain",
        "data_base64": BASE64.encode(secret_bytes),
        "conversation_id": "conv_group_office"
    });
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/upload")
                .header("authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(secret_upload_req.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let secret_uploaded: Value = serde_json::from_slice(&body_bytes).unwrap();
    let secret_key = secret_uploaded["key"].as_str().unwrap().to_string();
    let secret_url = secret_uploaded["url"].as_str().unwrap().to_string();

    // Send confidential message with attachment
    let conf_msg_req = json!({
        "type": "file",
        "content": "สัญญาความลับส่งผิดห้อง",
        "is_confidential": true,
        "confidential_pin": "1234",
        "attachment": {
            "key": secret_key,
            "url": secret_url,
            "file_name": "secret_contract.txt",
            "mime_type": "text/plain",
            "file_size": secret_bytes.len()
        }
    });
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/conversations/conv_group_office/messages")
                .header("authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(conf_msg_req.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let sent_conf: Value = serde_json::from_slice(&body_bytes).unwrap();
    assert_eq!(sent_conf["is_confidential"], true);
    let conf_msg_id = sent_conf["id"].as_str().unwrap().to_string();

    // Purge the accidental message -> must delete from MinIO and DB
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/api/messages/{}/purge", conf_msg_id))
                .header("authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let purge_res: Value = serde_json::from_slice(&body_bytes).unwrap();
    assert_eq!(purge_res["hard_deleted"], true);
    assert_eq!(purge_res["file_purged"], true);

    // Verify file is gone from MinIO (404 Not Found)
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{}", secret_key))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::NOT_FOUND);

    // 9. Test DeepSeek AI Summarize & Assist & @ai Co-Pilot + Secret Key Masking
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/ai/summarize")
                .header("authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({ "conversation_id": "conv_group_office" }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let sum_json: Value = serde_json::from_slice(&body_bytes).unwrap();
    assert!(!sum_json["summary"].as_str().unwrap().is_empty());
    assert!(!sum_json["action_items"].as_array().unwrap().is_empty());

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/ai/assist")
                .header("authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "conversation_id": "conv_group_office",
                        "prompt": "ส่งใบเสนอราคาให้ลูกค้าตรวจแล้ว",
                        "mode": "polish"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let assist_json: Value = serde_json::from_slice(&body_bytes).unwrap();
    assert!(!assist_json["result"].as_str().unwrap().is_empty());
    assert!(!assist_json["suggestions"].as_array().unwrap().is_empty());

    // Mention @ai in group chat -> AI Co-Pilot auto-replies in the room
    let ai_mention_req = json!({
        "type": "text",
        "content": "@ai สรุปงานในกลุ่มนี้ให้หน่อยครับ"
    });
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/conversations/conv_group_office/messages")
                .header("authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(ai_mention_req.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);

    // Verify AI reply was posted into conv_group_office
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/conversations/conv_group_office/messages")
                .header("authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let msgs_after_ai: Value = serde_json::from_slice(&body_bytes).unwrap();
    let last_msg = msgs_after_ai.as_array().unwrap().last().unwrap();
    assert_eq!(last_msg["sender_id"], "user_ai");

    // Verify AI Settings never leak raw api_key
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/admin/ai-settings")
                .header("authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let ai_settings: Value = serde_json::from_slice(&body_bytes).unwrap();
    assert!(ai_settings.get("api_key").is_none());
    assert_eq!(ai_settings["model"], "deepseek-chat");

    // 10. Test Urgent Task Action, Approve Card, and Admin Handover
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/messages/msg_group_urgent_task/task-action")
                .header("authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(json!({ "action": "done" }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let updated_task: Value = serde_json::from_slice(&body_bytes).unwrap();
    assert_eq!(updated_task["task_status"], "done");

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/messages/msg_group_flex_card/approve-card")
                .header("authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({ "status": "อนุมัติแล้ว", "comment": "อนุมัติด่วน" }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let approved_card: Value = serde_json::from_slice(&body_bytes).unwrap();
    assert_eq!(approved_card["flex_payload"]["status"], "อนุมัติแล้ว");

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/admin/handover")
                .header("authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "from_user_id": "user_somchai",
                        "to_user_id": "user_nida"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
        .await
        .unwrap();
    let handover_res: Value = serde_json::from_slice(&body_bytes).unwrap();
    assert_eq!(handover_res["status"], "ok");
    assert!(handover_res["transferred_conversations"].as_u64().unwrap() >= 1);
}
