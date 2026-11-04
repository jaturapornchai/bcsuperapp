use bcapp_backend::{config::AppConfig, create_router, seed::seed_initial_data, AppState};
use std::net::SocketAddr;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "bcapp_backend=info,tower_http=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let config = AppConfig::from_env();
    let port = config.port;

    let state = AppState::init(config)
        .await
        .expect("Failed to initialize AppState");

    if let Err(e) = seed_initial_data(&state).await {
        tracing::error!("Seed initial data error: {}", e);
    } else {
        tracing::info!("Seeded initial MongoDB & MinIO data successfully");
    }

    let app = create_router(state);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("BC Super App Backend listening on http://127.0.0.1:{}", port);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("Failed to bind port");
    axum::serve(listener, app)
        .await
        .expect("Server terminated unexpectedly");
}
