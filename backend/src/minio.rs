use chrono::Utc;
use hmac::{Hmac, Mac};
use reqwest::Client;
use sha2::{Digest, Sha256};

type HmacSha256 = Hmac<Sha256>;

#[derive(Clone)]
pub struct MinioClient {
    pub endpoint: String,
    pub host: String,
    pub access_key: String,
    pub secret_key: String,
    pub bucket: String,
    pub http: Client,
}

impl MinioClient {
    pub fn new(endpoint: &str, access_key: &str, secret_key: &str, bucket: &str) -> Self {
        let clean_endpoint = endpoint.trim_end_matches('/').to_string();
        let host = clean_endpoint
            .strip_prefix("http://")
            .or_else(|| clean_endpoint.strip_prefix("https://"))
            .unwrap_or(&clean_endpoint)
            .to_string();

        Self {
            endpoint: clean_endpoint,
            host,
            access_key: access_key.to_string(),
            secret_key: secret_key.to_string(),
            bucket: bucket.to_string(),
            http: Client::new(),
        }
    }

    fn hmac_sha256(key: &[u8], data: &[u8]) -> Vec<u8> {
        let mut mac = HmacSha256::new_from_slice(key).expect("HMAC can take key of any size");
        mac.update(data);
        mac.finalize().into_bytes().to_vec()
    }

    fn sha256_hex(data: &[u8]) -> String {
        let mut hasher = Sha256::new();
        hasher.update(data);
        hex::encode(hasher.finalize())
    }

    fn sign_request(
        &self,
        method: &str,
        canonical_uri: &str,
        payload: &[u8],
    ) -> (String, String, String) {
        let now = Utc::now();
        let amz_date = now.format("%Y%m%dT%H%M%SZ").to_string();
        let date_stamp = now.format("%Y%m%d").to_string();
        let region = "us-east-1";
        let service = "s3";

        let payload_hash = Self::sha256_hex(payload);
        let canonical_headers = format!(
            "host:{}\nx-amz-content-sha256:{}\nx-amz-date:{}\n",
            self.host, payload_hash, amz_date
        );
        let signed_headers = "host;x-amz-content-sha256;x-amz-date";

        let canonical_request = format!(
            "{}\n{}\n\n{}\n{}\n{}",
            method, canonical_uri, canonical_headers, signed_headers, payload_hash
        );

        let credential_scope = format!("{}/{}/{}/aws4_request", date_stamp, region, service);
        let string_to_sign = format!(
            "AWS4-HMAC-SHA256\n{}\n{}\n{}",
            amz_date,
            credential_scope,
            Self::sha256_hex(canonical_request.as_bytes())
        );

        let k_secret = format!("AWS4{}", self.secret_key);
        let k_date = Self::hmac_sha256(k_secret.as_bytes(), date_stamp.as_bytes());
        let k_region = Self::hmac_sha256(&k_date, region.as_bytes());
        let k_service = Self::hmac_sha256(&k_region, service.as_bytes());
        let k_signing = Self::hmac_sha256(&k_service, b"aws4_request");
        let signature = hex::encode(Self::hmac_sha256(&k_signing, string_to_sign.as_bytes()));

        let authorization = format!(
            "AWS4-HMAC-SHA256 Credential={}/{}, SignedHeaders={}, Signature={}",
            self.access_key, credential_scope, signed_headers, signature
        );

        (amz_date, payload_hash, authorization)
    }

    pub async fn check_health(&self) -> bool {
        let url = format!("{}/minio/health/live", self.endpoint);
        match self.http.get(&url).send().await {
            Ok(resp) => resp.status().is_success(),
            Err(_) => false,
        }
    }

    pub async fn ensure_bucket(&self) -> Result<(), String> {
        let uri = format!("/{}", self.bucket);
        let url = format!("{}{}", self.endpoint, uri);

        let (amz_date, payload_hash, auth) = self.sign_request("HEAD", &uri, b"");
        let head_res = self
            .http
            .head(&url)
            .header("Host", &self.host)
            .header("x-amz-date", &amz_date)
            .header("x-amz-content-sha256", &payload_hash)
            .header("Authorization", &auth)
            .send()
            .await
            .map_err(|e| format!("MinIO HEAD bucket error: {}", e))?;

        if head_res.status().is_success() {
            return Ok(());
        }

        let (amz_date, payload_hash, auth) = self.sign_request("PUT", &uri, b"");
        let put_res = self
            .http
            .put(&url)
            .header("Host", &self.host)
            .header("x-amz-date", &amz_date)
            .header("x-amz-content-sha256", &payload_hash)
            .header("Authorization", &auth)
            .send()
            .await
            .map_err(|e| format!("MinIO PUT bucket error: {}", e))?;

        if put_res.status().is_success() || put_res.status().as_u16() == 409 {
            Ok(())
        } else {
            let status = put_res.status();
            let text = put_res.text().await.unwrap_or_default();
            Err(format!("MinIO create bucket failed ({}): {}", status, text))
        }
    }

    pub fn sanitize_key(raw_key: &str) -> String {
        raw_key
            .chars()
            .map(|c| {
                if c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_' {
                    c
                } else {
                    '_'
                }
            })
            .collect()
    }

    pub async fn put_object(
        &self,
        key: &str,
        data: &[u8],
        content_type: &str,
    ) -> Result<(), String> {
        let safe_key = Self::sanitize_key(key);
        let uri = format!("/{}/{}", self.bucket, safe_key);
        let url = format!("{}{}", self.endpoint, uri);
        let (amz_date, payload_hash, auth) = self.sign_request("PUT", &uri, data);

        let res = self
            .http
            .put(&url)
            .header("Host", &self.host)
            .header("x-amz-date", &amz_date)
            .header("x-amz-content-sha256", &payload_hash)
            .header("Authorization", &auth)
            .header("Content-Type", content_type)
            .body(data.to_vec())
            .send()
            .await
            .map_err(|e| format!("MinIO put_object error: {}", e))?;

        if res.status().is_success() {
            Ok(())
        } else {
            let status = res.status();
            let text = res.text().await.unwrap_or_default();
            Err(format!("MinIO upload failed ({}): {}", status, text))
        }
    }

    pub async fn get_object(&self, key: &str) -> Result<(Vec<u8>, String), String> {
        let safe_key = Self::sanitize_key(key);
        let uri = format!("/{}/{}", self.bucket, safe_key);
        let url = format!("{}{}", self.endpoint, uri);
        let (amz_date, payload_hash, auth) = self.sign_request("GET", &uri, b"");

        let res = self
            .http
            .get(&url)
            .header("Host", &self.host)
            .header("x-amz-date", &amz_date)
            .header("x-amz-content-sha256", &payload_hash)
            .header("Authorization", &auth)
            .send()
            .await
            .map_err(|e| format!("MinIO get_object error: {}", e))?;

        if !res.status().is_success() {
            return Err(format!("MinIO get_object status: {}", res.status()));
        }

        let content_type = res
            .headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("application/octet-stream")
            .to_string();

        let bytes = res
            .bytes()
            .await
            .map_err(|e| format!("MinIO read bytes error: {}", e))?
            .to_vec();

        Ok((bytes, content_type))
    }

    pub async fn delete_object(&self, key: &str) -> Result<(), String> {
        let safe_key = Self::sanitize_key(key);
        let uri = format!("/{}/{}", self.bucket, safe_key);
        let url = format!("{}{}", self.endpoint, uri);
        let (amz_date, payload_hash, auth) = self.sign_request("DELETE", &uri, b"");

        let res = self
            .http
            .delete(&url)
            .header("Host", &self.host)
            .header("x-amz-date", &amz_date)
            .header("x-amz-content-sha256", &payload_hash)
            .header("Authorization", &auth)
            .send()
            .await
            .map_err(|e| format!("MinIO delete_object error: {}", e))?;

        if res.status().is_success() || res.status().as_u16() == 404 {
            Ok(())
        } else {
            let status = res.status();
            let text = res.text().await.unwrap_or_default();
            Err(format!("MinIO delete failed ({}): {}", status, text))
        }
    }
}
