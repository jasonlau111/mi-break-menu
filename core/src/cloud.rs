//! Xiaomi QR login and encrypted device discovery. Credentials travel only over private pipes.
use super::E;
use base64::{engine::general_purpose::STANDARD as B64, Engine};
use rand::RngCore;
use reqwest::blocking::Client;
use serde_json::{json, Value};
use sha1::Digest;
use std::{
    io::Write,
    os::unix::fs::OpenOptionsExt,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
fn parse(s: &str) -> Result<Value, E> {
    Ok(serde_json::from_str(
        s.strip_prefix("&&&START&&&").unwrap_or(s),
    )?)
}
fn rc4(key: &[u8], input: &[u8]) -> Vec<u8> {
    let mut s = [0u8; 256];
    for (i, v) in s.iter_mut().enumerate() {
        *v = i as u8
    }
    let mut j = 0usize;
    for i in 0..256 {
        j = (j + s[i] as usize + key[i % key.len()] as usize) % 256;
        s.swap(i, j)
    }
    let (mut i, mut j) = (0usize, 0usize);
    let mut out = Vec::new();
    for n in 0..1024 + input.len() {
        i = (i + 1) % 256;
        j = (j + s[i] as usize) % 256;
        s.swap(i, j);
        let b = s[(s[i] as usize + s[j] as usize) % 256];
        if n >= 1024 {
            out.push(input[n - 1024] ^ b)
        }
    }
    out
}
fn signature(path: &str, key: &str, fields: &[(String, String)]) -> String {
    let mut parts = vec!["POST".to_string(), path.to_string()];
    parts.extend(fields.iter().map(|(k, v)| format!("{k}={v}")));
    parts.push(key.into());
    B64.encode(sha1::Sha1::digest(parts.join("&").as_bytes()))
}
fn api(
    c: &Client,
    region: &str,
    user: &str,
    token: &str,
    sec: &str,
    path: &str,
    data: Value,
) -> Result<Value, E> {
    let mut nonce = [0u8; 12];
    rand::thread_rng().fill_bytes(&mut nonce[..8]);
    let minutes = (SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() / 60) as u32;
    nonce[8..].copy_from_slice(&minutes.to_be_bytes());
    let key = sha2::Sha256::digest([B64.decode(sec)?, nonce.to_vec()].concat());
    let signed = B64.encode(key);
    let mut fields = vec![("data".into(), data.to_string())];
    fields.push(("rc4_hash__".into(), signature(path, &signed, &fields)));
    for (_, v) in &mut fields {
        *v = B64.encode(rc4(&key, v.as_bytes()))
    }
    fields.push(("signature".into(), signature(path, &signed, &fields)));
    fields.push(("ssecurity".into(), sec.into()));
    fields.push(("_nonce".into(), B64.encode(nonce)));
    let prefix = if region == "cn" {
        String::new()
    } else {
        format!("{region}.")
    };
    let response = c
        .post(format!("https://{prefix}api.io.mi.com/app{path}"))
        .header("MIOT-ENCRYPT-ALGORITHM", "ENCRYPT-RC4")
        .header("x-xiaomi-protocal-flag-cli", "PROTOCAL-HTTP2")
        .header(
            "Cookie",
            format!(
                "userId={user}; serviceToken={token}; yetAnotherServiceToken={token}; locale=zh_CN"
            ),
        )
        .form(&fields)
        .send()?
        .error_for_status()?
        .text()?;
    let v: Value = serde_json::from_slice(&rc4(&key, &B64.decode(response.trim())?))?;
    if v["code"].as_i64() != Some(0) {
        return Err("米家接口拒绝请求，请检查地区或重新扫码".into());
    }
    Ok(v)
}
struct QR(std::path::PathBuf);
impl Drop for QR {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}
pub fn pair(r: &Value) -> Result<Value, E> {
    let region = r["region"].as_str().unwrap_or("cn");
    if !["cn", "de", "us", "ru", "tw", "sg", "in", "i2"].contains(&region) {
        return Err("不支持的地区".into());
    }
    let c = Client::builder()
        .cookie_store(true)
        .timeout(Duration::from_secs(15))
        .user_agent("MiBreakMenu APP/com.xiaomi.mihome APPV/10.5.201")
        .build()?;
    let login = parse(
        &c.get("https://account.xiaomi.com/longPolling/loginUrl")
            .query(&[
                ("_qrsize", "480"),
                ("qs", "%3Fsid%3Dxiaomiio%26_json%3Dtrue"),
                ("callback", "https://sts.api.io.mi.com/sts"),
                ("_hasLogo", "false"),
                ("sid", "xiaomiio"),
                ("serviceParam", ""),
                ("_locale", "zh_CN"),
            ])
            .send()?
            .error_for_status()?
            .text()?,
    )?;
    let qr = login["qr"].as_str().ok_or("无法获取登录二维码")?;
    let path = std::path::PathBuf::from(r["qr"].as_str().ok_or("缺少二维码路径")?);
    let guard = QR(path);
    let bytes = c.get(qr).send()?.error_for_status()?.bytes()?;
    if bytes.len() > 1_000_000 {
        return Err("二维码响应异常".into());
    }
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&guard.0)?;
    f.write_all(&bytes)?;
    drop(f);
    let until = std::time::Instant::now() + Duration::from_secs(150);
    let poll = login["lp"].as_str().ok_or("登录服务未返回等待地址")?;
    let result = loop {
        if std::time::Instant::now() >= until {
            return Err("二维码已过期，请重新扫码".into());
        }
        match c.get(poll).send() {
            Ok(resp) => {
                if resp.status().is_success() {
                    break parse(&resp.text()?)?;
                }
            }
            Err(e) if e.is_timeout() => continue,
            Err(_) => return Err("扫码登录连接中断".into()),
        }
    };
    let user = result["userId"]
        .as_str()
        .map(str::to_string)
        .or_else(|| result["userId"].as_u64().map(|v| v.to_string()))
        .ok_or("登录尚未确认")?;
    let sec = result["ssecurity"].as_str().ok_or("登录尚未确认")?;
    let location = result["location"].as_str().ok_or("登录尚未确认")?;
    let response = c.get(location).send()?.error_for_status()?;
    let token = response
        .cookies()
        .find(|v| v.name() == "serviceToken")
        .map(|v| v.value().to_string())
        .ok_or("无法完成米家登录")?;
    let homes = api(
        &c,
        region,
        &user,
        &token,
        sec,
        "/v2/homeroom/gethome",
        json!({"fg":true,"fetch_share":true,"fetch_share_dev":true,"limit":300,"app_ver":7}),
    )?;
    let mut all = Vec::new();
    if let Some(hs) = homes["result"]["homelist"].as_array() {
        for h in hs {
            all.push((h["id"].clone(), json!(user.parse::<u64>()?)))
        }
    }
    let shared = api(
        &c,
        region,
        &user,
        &token,
        sec,
        "/v2/user/get_device_cnt",
        json!({"fetch_own":true,"fetch_share":true}),
    )?;
    if let Some(hs) = shared["result"]["share"]["share_family"].as_array() {
        for h in hs {
            all.push((h["home_id"].clone(), h["home_owner"].clone()))
        }
    }
    let mut devices = Vec::new();
    for (home, owner) in all {
        let d = api(
            &c,
            region,
            &user,
            &token,
            sec,
            "/v2/home/home_device_list",
            json!({"home_owner":owner,"home_id":home,"limit":200,"get_split_device":true,"support_smart_home":true}),
        )?;
        if let Some(ds) = d["result"]["device_info"].as_array() {
            for dev in ds {
                let model = dev["model"].as_str().unwrap_or("");
                if model.contains("sensor_occupy") {
                    let item = json!({"name":dev["name"],"model":model,"did":dev["did"],"supported":model == "xiaomi.sensor_occupy.03"});
                    if !devices.iter().any(|d: &Value| d["did"] == item["did"]) {
                        devices.push(item)
                    }
                }
            }
        }
    }
    Ok(
        json!({"devices":devices,"session":{"region":region,"user":user,"token":token,"security":sec}}),
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rc4_roundtrip() {
        let k = b"0123456789012345";
        assert_eq!(rc4(k, &rc4(k, b"hello")), b"hello");
    }
    #[test]
    fn prefix() {
        assert_eq!(parse("&&&START&&&{\"code\":0}").unwrap()["code"], 0);
    }
}

pub fn read(r: &Value) -> Result<Value, E> {
    let session = &r["session"];
    let region = session["region"].as_str().ok_or("缺少登录地区")?;
    if !["cn", "de", "us", "ru", "tw", "sg", "in", "i2"].contains(&region) {
        return Err("不支持的地区".into());
    }
    let user = session["user"].as_str().ok_or("缺少登录会话")?;
    let token = session["token"].as_str().ok_or("缺少登录会话")?;
    let sec = session["security"].as_str().ok_or("缺少登录会话")?;
    let did = r["did"].as_str().ok_or("缺少设备标识")?;
    if r["model"] != "xiaomi.sensor_occupy.03" {
        return Err("该型号尚未适配，请勿按其他型号解释数据".into());
    }
    let c = Client::builder()
        .timeout(Duration::from_secs(12))
        .user_agent("MiBreakMenu APP/com.xiaomi.mihome APPV/10.5.201")
        .build()?;
    let devices = api(
        &c,
        region,
        user,
        token,
        sec,
        "/home/device_list",
        json!({"getVirtualModel":true,"getHuamiDevices":1,"get_split_device":false,"support_smart_home":true}),
    )?;
    let device = devices["result"]["list"]
        .as_array()
        .and_then(|ds| ds.iter().find(|d| d["did"] == did))
        .ok_or("设备列表中找不到已绑定传感器")?;
    if device["model"] != r["model"] {
        return Err("传感器型号发生变化，请重新绑定".into());
    }
    let online = device["isOnline"].as_bool();
    if online != Some(true) {
        return Ok(
            json!({"reading":{"presence":"unknown","online":online,"note":"米家未确认传感器在线，计时已暂停"}}),
        );
    }
    let reply = api(
        &c,
        region,
        user,
        token,
        sec,
        "/miotspec/prop/get",
        json!({"params":[{"did":did,"siid":2,"piid":1078}]}),
    )?;
    let presence = decode_presence(&reply, did)?;
    Ok(
        json!({"reading":{"presence":presence,"online":true,"deviceName":device["name"],"note":"米家云端状态 · 约每15秒读取"}}),
    )
}

fn decode_presence(reply: &Value, did: &str) -> Result<&'static str, E> {
    let values = reply["result"].as_array().ok_or("传感器响应缺少属性列表")?;
    let p = values
        .iter()
        .find(|p| p["did"] == did && p["siid"] == 2 && p["piid"] == 1078)
        .ok_or("传感器响应缺少有人无人属性")?;
    if p["code"].as_i64() != Some(0) {
        return Err("云端暂时无法读取有人无人属性，需验证此型号接入".into());
    }
    Ok(match p["value"].as_u64() {
        Some(0) => "away",
        Some(1) => "seated",
        _ => "unknown",
    })
}

#[cfg(test)]
mod presence_tests {
    use super::*;
    #[test]
    fn identity_codes_and_quick_check_are_preserved() {
        for (value, expected) in [(0, "away"), (1, "seated"), (2, "unknown"), (99, "unknown")] {
            let r = json!({"result":[{"did":"test","siid":2,"piid":1078,"code":0,"value":value}]});
            assert_eq!(decode_presence(&r, "test").unwrap(), expected);
            assert!(decode_presence(&r, "other").is_err());
        }
        assert!(decode_presence(
            &json!({"result":[{"did":"test","siid":2,"piid":1078,"value":0}]}),
            "test"
        )
        .is_err());
        assert!(decode_presence(&json!({"result":null}), "test").is_err());
    }
}
