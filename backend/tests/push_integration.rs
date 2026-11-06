//! Push path end to end against a mock FCM: service-account JWT -> OAuth token
//! -> messages:send, plus device rules and UNREGISTERED clean-up.
//! Needs MongoDB (like api_integration) and `openssl` to make a throwaway key.

use std::{
    collections::HashMap,
    process::Command,
    sync::{Arc, Mutex},
    time::Duration,
};

use axum::{
    body::Body,
    extract::State,
    http::{HeaderMap, Request, StatusCode, Uri},
    routing::post,
    Form, Json, Router,
};
use bcapp_backend::{
    config::AppConfig,
    create_router,
    seed::{seed_initial_data, TEST_ACCOUNTS},
    AppState,
};
use jsonwebtoken::{Algorithm, DecodingKey, Validation};
use serde_json::{json, Value};
use tower::ServiceExt;

#[derive(Clone, Default)]
struct MockFcm {
    assertions: Arc<Mutex<Vec<String>>>,
    sends: Arc<Mutex<Vec<Value>>>,
}

async fn mock_token(
    State(m): State<MockFcm>,
    Form(form): Form<HashMap<String, String>>,
) -> Json<Value> {
    assert_eq!(form["grant_type"], "urn:ietf:params:oauth:grant-type:jwt-bearer");
    m.assertions.lock().unwrap().push(form["assertion"].clone());
    Json(json!({ "access_token": "mock-access", "expires_in": 3600, "token_type": "Bearer" }))
}

async fn mock_send(
    State(m): State<MockFcm>,
    uri: Uri,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> (StatusCode, Json<Value>) {
    assert_eq!(uri.path(), "/v1/projects/test-proj/messages:send");
    assert_eq!(headers["authorization"], "Bearer mock-access");
    let tok = body["message"]["token"].as_str().unwrap_or_default().to_string();
    let dead = tok == "dead-token";
    let prev_attempts = {
        let mut sends = m.sends.lock().unwrap();
        let count = sends
            .iter()
            .filter(|s| s["message"]["token"].as_str() == Some(tok.as_str()))
            .count();
        sends.push(body);
        count
    };
    if tok.starts_with("tok-503-") && prev_attempts == 0 {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({ "error": { "code": 503, "status": "UNAVAILABLE",
                "message": "The service is currently unavailable." } })),
        );
    }
    if dead {
        return (
            StatusCode::NOT_FOUND,
            Json(json!({ "error": { "code": 404, "status": "NOT_FOUND",
                "message": "Requested entity was not found.",
                "details": [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
                              "errorCode": "UNREGISTERED" }] } })),
        );
    }
    (StatusCode::OK, Json(json!({ "name": "projects/test-proj/messages/1" })))
}

fn openssl(args: &[&str]) -> String {
    let out = Command::new("openssl").args(args).output().expect("openssl on PATH");
    assert!(out.status.success(), "openssl {args:?} failed");
    String::from_utf8(out.stdout).unwrap()
}

#[tokio::test]
async fn test_push_to_offline_devices_through_fcm() {
    // Throwaway RSA key in PKCS#8, the same format Google service accounts use.
    let dir = std::env::temp_dir().join(format!("bcapp_push_{}", uuid::Uuid::new_v4().simple()));
    std::fs::create_dir_all(&dir).unwrap();
    let key_file = dir.join("key.pem");
    let private_pem = openssl(&["genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048"]);
    std::fs::write(&key_file, &private_pem).unwrap();
    let public_pem = openssl(&["pkey", "-in", key_file.to_str().unwrap(), "-pubout"]);

    let mock = MockFcm::default();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let mock_app = Router::new()
        .route("/token", post(mock_token))
        .fallback(mock_send)
        .with_state(mock.clone());
    tokio::spawn(async move { axum::serve(listener, mock_app).await.unwrap() });

    let sa_file = dir.join("service-account.json");
    std::fs::write(&sa_file, json!({
        "type": "service_account",
        "project_id": "test-proj",
        "private_key_id": "test-key-id",
        "private_key": private_pem,
        "client_email": "push@test-proj.example.com",
        "token_uri": format!("{base}/token"),
    }).to_string()).unwrap();

    let mut config = AppConfig::from_env();
    config.fcm_service_account_file = sa_file.to_string_lossy().into_owned();
    config.fcm_api_base = base.clone();
    config.fcm_web_api_key.clear(); // web config stays off without all FCM_WEB_*
    let state = AppState::init(config).await.expect("init AppState");
    assert!(state.push.is_some(), "push must load the service account");
    seed_initial_data(&state).await.expect("seed");
    let devices = state.db.collection::<bson::Document>("device_tokens");
    devices.delete_many(bson::doc! { "_id": { "$regex": "^test-" } }).await.unwrap();
    let app = create_router(state.clone());

    let mut tokens = Vec::new();
    for (_, email, name) in &TEST_ACCOUNTS[..5] {
        let (status, body) = call(&app, "POST", "/api/auth/google", None,
            Some(json!({ "email": email, "display_name": name }))).await;
        assert_eq!(status, StatusCode::OK);
        tokens.push(body["token"].as_str().unwrap().to_string());
    }
    let run = uuid::Uuid::new_v4().simple().to_string();
    let dev = |n: usize| format!("test-{n}-{run}");
    let sounds = json!({ "normal": "chime", "urgent": "urgent", "ai": "robot" });
    let register = |n: usize, token: &str, popup: bool| json!({
        "device_id": dev(n), "token": token, "platform": "android",
        "popup": popup, "sound": true, "sounds": sounds });

    // Input rules.
    let mut bad = register(9, "tok", true);
    bad["platform"] = json!("windows");
    let (status, _) = call(&app, "POST", "/api/devices", Some(&tokens[1]), Some(bad)).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let mut bad = register(9, "tok", true);
    bad["sounds"]["normal"] = json!("../../etc");
    let (status, _) = call(&app, "POST", "/api/devices", Some(&tokens[1]), Some(bad)).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = call(&app, "POST", "/api/devices", None, Some(register(9, "tok", true))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    // tester1 = sender, 2 = normal, 3 = token FCM no longer knows, 4 = pop-ups off, 5 = 503 then 200.
    let ok_token = format!("tok-ok-{run}");
    let own_token = format!("tok-own-{run}");
    let flaky_token = format!("tok-503-{run}");
    for (i, (token, popup)) in [(own_token.as_str(), true), (ok_token.as_str(), true),
                                ("dead-token", true), ("tok-quiet", false),
                                (flaky_token.as_str(), true)].into_iter().enumerate() {
        let (status, body) = call(&app, "POST", "/api/devices", Some(&tokens[i]),
            Some(register(i + 1, token, popup))).await;
        assert_eq!(status, StatusCode::OK, "{body}");
        assert_eq!(body["push"], true);
    }
    // Only the owner can remove a device.
    let (status, _) = call(&app, "DELETE", &format!("/api/devices/{}", dev(2)), Some(&tokens[0]), None).await;
    assert_eq!(status, StatusCode::OK);
    let devices = state.db.collection::<bson::Document>("device_tokens");
    assert!(devices.find_one(bson::doc! { "_id": dev(2) }).await.unwrap().is_some());

    let (status, cfg) = call(&app, "GET", "/api/push/config", Some(&tokens[1]), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(cfg, json!({ "enabled": true, "web": null }));

    let text = format!("ทดสอบ push {run}");
    let (status, _) = call(&app, "POST", "/api/conversations/conv_group_test5/messages",
        Some(&tokens[0]), Some(json!({ "type": "text", "content": text }))).await;
    assert_eq!(status, StatusCode::OK);

    let mut gone = false;
    for _ in 0..30 {
        tokio::time::sleep(Duration::from_millis(50)).await;
        let sent = mock.sends.lock().unwrap().len();
        gone = devices.find_one(bson::doc! { "_id": dev(3) }).await.unwrap().is_none();
        if sent >= 4 && gone {
            break;
        }
    }
    let sends = mock.sends.lock().unwrap().clone();
    let to: Vec<&str> = sends.iter().filter_map(|s| s["message"]["token"].as_str()).collect();
    assert_eq!(
        to.iter().filter(|&&t| t == flaky_token.as_str()).count(),
        2,
        "503 response must be retried and succeed on the next attempt: {to:?}"
    );
    assert_eq!(sends.len(), 4, "offline devices with pop-ups on (including 1 retry): {to:?}");
    assert!(to.contains(&ok_token.as_str()) && to.contains(&"dead-token"));
    assert!(gone, "UNREGISTERED token must be deleted");
    assert!(
        devices.find_one(bson::doc! { "_id": dev(5) }).await.unwrap().is_some(),
        "transient 503 token must not be deleted"
    );

    let msg = &sends.iter().find(|s| s["message"]["token"] == ok_token.as_str()).unwrap()["message"];
    assert_eq!(msg["data"]["conversation_id"], "conv_group_test5");
    assert_eq!(msg["data"]["silent"], "0");
    assert_eq!(msg["android"]["priority"], "high");
    assert_eq!(msg["android"]["notification"]["channel_id"], "push_chime");
    assert_eq!(msg["android"]["notification"]["sound"], "alert_chime");
    assert_eq!(msg["android"]["notification"]["tag"], "conv_group_test5");
    assert_eq!(msg["android"]["notification"]["title"], "ห้องทดสอบแชท 5 คน");
    assert_eq!(msg["android"]["notification"]["body"], format!("{}: {text}", TEST_ACCOUNTS[0].2));

    // One OAuth exchange, with an RS256 JWT Google would accept.
    let assertions = mock.assertions.lock().unwrap().clone();
    assert_eq!(assertions.len(), 1, "access token must be cached");
    let mut v = Validation::new(Algorithm::RS256);
    v.set_audience(&[format!("{base}/token")]);
    v.set_issuer(&["push@test-proj.example.com"]);
    let jwt = jsonwebtoken::decode::<Value>(&assertions[0],
        &DecodingKey::from_rsa_pem(public_pem.as_bytes()).unwrap(), &v).expect("valid JWT");
    assert_eq!(jwt.header.kid.as_deref(), Some("test-key-id"));
    assert_eq!(jwt.claims["scope"], "https://www.googleapis.com/auth/firebase.messaging");

    for i in [1, 2, 4, 5] {
        let (status, _) = call(&app, "DELETE", &format!("/api/devices/{}", dev(i)), Some(&tokens[i - 1]), None).await;
        assert_eq!(status, StatusCode::OK);
    }
    assert_eq!(devices.count_documents(bson::doc! { "_id": { "$regex": run.as_str() } }).await.unwrap(), 0);
    let _ = std::fs::remove_dir_all(&dir);
}

async fn call(
    app: &Router,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut req = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let req = match body {
        Some(b) => req.header("content-type", "application/json").body(Body::from(b.to_string())),
        None => req.body(Body::empty()),
    }
    .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}
