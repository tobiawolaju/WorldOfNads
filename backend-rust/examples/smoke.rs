//! Live smoke client: connects to the running room server, sends an
//! `update_state`, and prints the decoded (MessagePack -> JSON) frames it gets
//! back. Run: `cargo run --example smoke -- ws://127.0.0.1:8080?username=smoke`

use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::tungstenite::Message;

#[tokio::main]
async fn main() {
    let url = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "ws://127.0.0.1:8080?username=smoke-client".to_string());

    println!("connecting to {}", url);
    let (mut ws, _res) = tokio_tungstenite::connect_async(&url)
        .await
        .expect("connect failed");

    let update = serde_json::json!({
        "type": "update_state",
        "qx": 100, "qy": 0, "qz": 100, "qrot": 0, "anim_id": 1
    });
    let payload = rmp_serde::to_vec_named(&update).unwrap();
    ws.send(Message::Binary(payload)).await.unwrap();

    let mut seen = 0;
    while let Some(msg) = ws.next().await {
        match msg {
            Ok(Message::Binary(bytes)) => {
                let value: serde_json::Value = rmp_serde::from_slice(&bytes).unwrap();
                let kind = value.get("type").cloned().unwrap_or_default();
                println!("<- {}", serde_json::to_string(&value).unwrap());
                seen += 1;
                if kind == "state_full" && seen >= 2 {
                    break;
                }
            }
            Ok(Message::Ping(payload)) => {
                let _ = ws.send(Message::Pong(payload)).await;
            }
            Ok(Message::Close(_)) => break,
            Ok(_) => {}
            Err(error) => {
                eprintln!("socket error: {}", error);
                break;
            }
        }
    }

    println!("done ({} frames)", seen);
}
