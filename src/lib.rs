use spin_sdk::http::{IntoResponse, Request, Response};
use spin_sdk::http_service;

/// A simple Spin HTTP component.
#[http_service]
async fn handle_rust(req: Request) -> anyhow::Result<impl IntoResponse> {
    let mut response_body = String::new();
    for (name, value) in req.headers() {
        response_body.push_str(&format!("{name}: {}\n", value.to_str()?));
        println!("{name}: {}", value.to_str()?);
    }

    Ok(Response::builder()
        .status(200)
        .header("content-type", "text/plain")
        .body(response_body)?)
}
