mod cloud;
use serde_json::{json, Value};
use std::io::{Read, Write};
type E = Box<dyn std::error::Error + Send + Sync>;
fn run() -> Result<Value, E> {
    let mut input = String::new();
    std::io::stdin().take(65537).read_to_string(&mut input)?;
    if input.len() > 65536 {
        return Err("请求过大".into());
    }
    let request: Value = serde_json::from_str(&input)?;
    match request["op"].as_str() {
        Some("pair") => cloud::pair(&request),
        Some("read") => cloud::read(&request),
        _ => Err("不支持的操作".into()),
    }
}
fn main() {
    // Never echo transport errors: URLs and cookies can contain authentication material.
    let reply = match run() {
        Ok(v) => v,
        Err(e) => {
            let msg = e.to_string();
            let safe = if msg
                .chars()
                .next()
                .is_some_and(|c| ('\u{4e00}'..='\u{9fff}').contains(&c))
            {
                msg
            } else {
                "连接或响应解析失败，请检查网络后重试".into()
            };
            json!({"error": safe})
        }
    };
    let _ = std::io::stdout().write_all(reply.to_string().as_bytes());
}
