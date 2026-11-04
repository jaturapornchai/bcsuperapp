use std::env;

#[derive(Clone, Debug)]
pub struct AppConfig {
    pub port: u16,
    pub mongodb_uri: String,
    pub mongodb_db: String,
    pub minio_endpoint: String,
    pub minio_access_key: String,
    pub minio_secret_key: String,
    pub minio_bucket: String,
    pub jwt_secret: String,
    pub google_client_id: String,
    pub super_admin_email: String,
    pub public_base_url: String,
    pub deepseek_api_key: String,
    pub deepseek_model: String,
    pub deepseek_base_url: String,
}

impl AppConfig {
    pub fn from_env() -> Self {
        if dotenvy::from_path("../.env").is_err() {
            let _ = dotenvy::dotenv();
        }

        let port = env::var("PORT")
            .ok()
            .and_then(|v| v.parse::<u16>().ok())
            .unwrap_or(8095);

        let mongodb_uri = env::var("MONGODB_URI")
            .unwrap_or_else(|_| "mongodb://127.0.0.1:27029".to_string());
        let mongodb_db = env::var("MONGODB_DB").unwrap_or_else(|_| "bcapp".to_string());

        let minio_endpoint = env::var("MINIO_ENDPOINT")
            .unwrap_or_else(|_| "http://127.0.0.1:9120".to_string())
            .trim_end_matches('/')
            .to_string();
        let minio_access_key = env::var("MINIO_ACCESS_KEY")
            .unwrap_or_else(|_| "bcappadmin".to_string());
        let minio_secret_key = env::var("MINIO_SECRET_KEY")
            .unwrap_or_else(|_| "bcapp_minio_local_dev".to_string());
        let minio_bucket = env::var("MINIO_BUCKET")
            .unwrap_or_else(|_| "bcapp-storage".to_string());

        let jwt_secret = env::var("JWT_SECRET")
            .unwrap_or_else(|_| "bcapp_super_secret_jwt_key_2026".to_string());
        let google_client_id = env::var("GOOGLE_CLIENT_ID")
            .unwrap_or_else(|_| "".to_string());
        let super_admin_email = env::var("SUPER_ADMIN_EMAIL")
            .unwrap_or_else(|_| "jead@bcapp.local".to_string());

        let public_base_url = env::var("PUBLIC_BASE_URL")
            .unwrap_or_else(|_| format!("http://127.0.0.1:{}", port));

        let deepseek_api_key = env::var("DEEPSEEK_API_KEY")
            .unwrap_or_default()
            .trim()
            .to_string();
        let deepseek_model = env::var("DEEPSEEK_MODEL")
            .unwrap_or_else(|_| "deepseek-chat".to_string())
            .trim()
            .to_string();
        let deepseek_base_url = env::var("DEEPSEEK_BASE_URL")
            .unwrap_or_else(|_| "https://api.deepseek.com".to_string())
            .trim_end_matches('/')
            .to_string();

        Self {
            port,
            mongodb_uri,
            mongodb_db,
            minio_endpoint,
            minio_access_key,
            minio_secret_key,
            minio_bucket,
            jwt_secret,
            google_client_id,
            super_admin_email,
            public_base_url,
            deepseek_api_key,
            deepseek_model,
            deepseek_base_url,
        }
    }
}
