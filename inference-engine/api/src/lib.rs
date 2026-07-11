use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{net::{IpAddr, Ipv4Addr, SocketAddr}, sync::Arc};

#[derive(Clone)]
struct AppState {
    runtime_mode: &'static str,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: &'static str,
    product: &'static str,
    runtime_mode: &'static str,
    api_version: &'static str,
}

#[derive(Debug, Deserialize)]
struct ChatCompletionRequest {
    #[allow(dead_code)]
    model: Option<String>,
    #[allow(dead_code)]
    messages: Option<Vec<Value>>,
}

async fn health(State(state): State<Arc<AppState>>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        product: "bitshit",
        runtime_mode: state.runtime_mode,
        api_version: "v1",
    })
}

async fn models() -> Json<Value> {
    Json(json!({
        "object": "list",
        "data": []
    }))
}

async fn chat_completions(Json(_request): Json<ChatCompletionRequest>) -> impl IntoResponse {
    (
        StatusCode::SERVICE_UNAVAILABLE,
        Json(json!({
            "error": {
                "type": "runtime_unavailable",
                "message": "The BitShit API daemon is running, but no inference runtime is attached yet. Start or configure a model runtime before requesting completions."
            }
        })),
    )
}

fn resolve_bind_addr() -> SocketAddr {
    let port = std::env::var("BITSHIT_PORT")
        .or_else(|_| std::env::var("CLUAIZ_PORT"))
        .or_else(|_| std::env::var("cluaiz_PORT"))
        .ok()
        .and_then(|value| value.parse::<u16>().ok())
        .unwrap_or(8000);

    let host = std::env::var("BITSHIT_HOST")
        .ok()
        .and_then(|value| value.parse::<IpAddr>().ok())
        .unwrap_or(IpAddr::V4(Ipv4Addr::LOCALHOST));

    SocketAddr::new(host, port)
}

pub async fn run_daemon() {
    let addr = resolve_bind_addr();
    let state = Arc::new(AppState {
        runtime_mode: "standalone",
    });

    let app = Router::new()
        .route("/health", get(health))
        .route("/v1/models", get(models))
        .route("/v1/chat/completions", post(chat_completions))
        .with_state(state);

    let listener = match tokio::net::TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(error) => {
            eprintln!("[BitShit] API bind failed on {addr}: {error}");
            return;
        }
    };

    println!("[BitShit] API listening on http://{addr}");

    if let Err(error) = axum::serve(listener, app).await {
        eprintln!("[BitShit] API server stopped: {error}");
    }
}
