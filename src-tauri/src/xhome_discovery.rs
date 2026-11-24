//! xHome server discovery, shared by both backend runners.
//!
//! Xbox returns remote-play servers per region. The default region can be
//! reachable while returning an empty result, so discovery tries every
//! advertised region before reporting no targets.

use reqwest::{Client, Url};
use serde_json::{Value, json};
use std::time::Duration;

const MAX_REGIONS: usize = 8;

pub fn regions(token: &Value) -> Result<Vec<(String, String)>, String> {
    let entries = token
        .pointer("/offeringSettings/regions")
        .and_then(Value::as_array)
        .ok_or("The xHome token has no region list")?;

    let mut ordered: Vec<_> = entries.iter().collect();
    ordered.sort_by_key(|region| {
        if region.get("isDefault").and_then(Value::as_bool) == Some(true) {
            0
        } else {
            1
        }
    });

    let mut result = Vec::new();
    for region in ordered.into_iter().take(MAX_REGIONS) {
        let Some(raw) = region.get("baseUri").and_then(Value::as_str) else {
            continue;
        };
        let Ok(mut url) = Url::parse(raw) else {
            continue;
        };
        let Some(host) = url.host_str().map(str::to_owned) else {
            continue;
        };
        if url.scheme() != "https"
            || !url.username().is_empty()
            || url.password().is_some()
            || url.port().is_some()
            || !(host == "xboxlive.com" || host.ends_with(".xboxlive.com"))
            || !matches!(url.path(), "" | "/")
            || url.query().is_some()
            || url.fragment().is_some()
        {
            continue;
        }
        url.set_path("");
        let label = region
            .get("name")
            .and_then(Value::as_str)
            .filter(|name| !name.is_empty())
            .unwrap_or(host.as_str())
            .chars()
            .filter(|ch| ch.is_ascii_alphanumeric() || *ch == '-' || *ch == '_')
            .take(32)
            .collect::<String>();
        result.push((label, format!("{}/v6/servers/home?mr=50", url.as_str().trim_end_matches('/'))));
    }
    if result.is_empty() {
        return Err("The xHome token contains no valid Xbox service regions".into());
    }
    Ok(result)
}

pub fn server_records(value: &Value) -> Option<Vec<Value>> {
    if let Some(array) = value.as_array() {
        return Some(array.clone());
    }
    for key in ["results", "servers", "result", "devices", "consoles"] {
        if let Some(nested) = value.get(key) {
            if nested.is_array() || nested.is_object() {
                if let Some(records) = server_records(nested) {
                    return Some(records);
                }
            }
        }
    }
    let object = value.as_object()?;
    if ["serverId", "server_id", "id"]
        .iter()
        .any(|key| object.get(*key).and_then(Value::as_str).is_some_and(|id| !id.is_empty()))
    {
        return Some(vec![value.clone()]);
    }

    // Some Xbox responses encode results as an object instead of an array.
    // Accept both a named envelope and a map keyed by server ID.
    for key in ["items", "servers", "server", "devices", "consoles", "values"] {
        if let Some(nested) = object.get(key) {
            if nested.is_array() || nested.is_object() {
                if let Some(records) = server_records(nested) {
                    return Some(records);
                }
            }
        }
    }
    if !object.is_empty() && object.values().all(Value::is_object) {
        return Some(
            object
                .iter()
                .map(|(key, value)| {
                    let mut record = value.clone();
                    if record.get("serverId").and_then(Value::as_str).is_none()
                        && record.get("server_id").and_then(Value::as_str).is_none()
                        && record.get("id").and_then(Value::as_str).is_none()
                    {
                        if let Some(record) = record.as_object_mut() {
                            record.insert("serverId".into(), Value::String(key.clone()));
                        }
                    }
                    record
                })
                .collect(),
        );
    }
    None
}

fn normalized_server_response(value: &Value) -> Option<Value> {
    let records = server_records(value)?;
    let mut normalized = value.clone();
    let object = normalized.as_object_mut()?;
    object.insert("results".into(), Value::Array(records));
    Some(normalized)
}

pub async fn list_servers(client: &Client, token: &Value) -> Result<Value, String> {
    let bearer = token
        .get("gsToken")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or("The xHome token has no streaming bearer")?;
    let regions = regions(token)?;
    let device_info = crate::session::home_discovery_device_info().to_string();
    let mut outcomes = Vec::new();
    let mut had_success = false;

    for (name, url) in regions {
        let response = match client
            .get(&url)
            .bearer_auth(bearer)
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .header("X-Gssv-Client", "XboxComBrowser")
            .header("X-MS-Device-Info", &device_info)
            .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36")
            .header("Cache-Control", "no-store, no-cache, must-revalidate")
            .header("Pragma", "no-cache")
            .timeout(Duration::from_secs(8))
            .send()
            .await
        {
            Ok(response) => response,
            Err(error) => {
                outcomes.push(json!({"region": name, "status": if error.is_timeout() { "timeout" } else { "network_error" }}));
                continue;
            }
        };

        let status = response.status();
        if status.as_u16() == 401 {
            return Err("Xbox Remote Play returned HTTP 401".into());
        }
        if !status.is_success() {
            outcomes.push(json!({"region": name, "status": "http_error", "httpStatus": status.as_u16()}));
            continue;
        }
        let value = match response.json::<Value>().await {
            Ok(value) => value,
            Err(_) => {
                had_success = true;
                outcomes.push(json!({"region": name, "status": "invalid_json"}));
                continue;
            }
        };
        had_success = true;
        match normalized_server_response(&value) {
            Some(normalized) if !normalized["results"].as_array().is_some_and(Vec::is_empty) => {
                return Ok(normalized)
            }
            Some(normalized) => outcomes.push(json!({
                "region": name,
                "status": "empty",
                "count": normalized["results"].as_array().map(Vec::len).unwrap_or(0)
            })),
            None => {
                let value_keys = value
                    .as_object()
                    .map(|object| object.keys().take(8).cloned().collect::<Vec<_>>())
                    .unwrap_or_default();
                let results = value.get("results");
                let results_type = match results {
                    Some(value) if value.is_array() => "array",
                    Some(value) if value.is_object() => "object",
                    Some(value) if value.is_string() => "string",
                    Some(value) if value.is_number() => "number",
                    Some(value) if value.is_boolean() => "boolean",
                    Some(_) => "other",
                    None => "missing",
                };
                let results_keys = results
                    .and_then(Value::as_object)
                    .map(|object| object.keys().take(8).cloned().collect::<Vec<_>>())
                    .unwrap_or_default();
                outcomes.push(json!({
                    "region": name,
                    "status": "unexpected_shape",
                    "keys": value_keys,
                    "resultsType": results_type,
                    "resultsKeys": results_keys
                }));
            }
        }
    }

    if had_success {
        return Ok(json!({
            "results": [],
            "_xjausDiscovery": {"regions": outcomes}
        }));
    }
    let brief = outcomes
        .iter()
        .filter_map(|entry| {
            Some(format!(
                "{}:{}{}",
                entry.get("region")?.as_str()?,
                entry.get("status")?.as_str()?,
                entry.get("httpStatus").and_then(Value::as_u64).map(|n| format!("/{n}")).unwrap_or_default()
            ))
        })
        .collect::<Vec<_>>()
        .join(", ");
    Err(format!("Xbox Remote Play lookup failed in all regions ({brief})"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn regions_try_default_first_and_include_all_supported_regions() {
        let token = json!({"offeringSettings":{"regions":[
            {"name":"EastUS","baseUri":"https://eus.core.gssv-play-prodxhome.xboxlive.com","isDefault":false},
            {"name":"WestUS2","baseUri":"https://wus2.core.gssv-play-prodxhome.xboxlive.com","isDefault":true}
        ]}});
        let regions = regions(&token).unwrap();
        assert_eq!(regions[0].0, "WestUS2");
        assert_eq!(regions[0].1, "https://wus2.core.gssv-play-prodxhome.xboxlive.com/v6/servers/home?mr=50");
        assert_eq!(regions[1].0, "EastUS");
    }

    #[test]
    fn regions_reject_non_xbox_hosts_and_userinfo() {
        let token = json!({"offeringSettings":{"regions":[
            {"name":"bad","baseUri":"https://attacker.example"},
            {"name":"bad2","baseUri":"https://user@wus2.core.gssv-play-prodxhome.xboxlive.com"}
        ]}});
        assert!(regions(&token).is_err());
    }

    #[test]
    fn response_records_accepts_known_shapes_and_rejects_unknown_shape() {
        assert_eq!(server_records(&json!({"results":[{"serverId":"x"}]})).unwrap().len(), 1);
        assert_eq!(server_records(&json!({"result":{"servers":[1]}})).unwrap().len(), 1);
        assert_eq!(
            server_records(&json!({"results":{"serverId":"x","name":"Xbox"}})).unwrap().len(),
            1
        );
        let mapped = server_records(&json!({"results":{"xbox-id":{"name":"Xbox"}}})).unwrap();
        assert_eq!(mapped[0]["serverId"], "xbox-id");
        assert!(server_records(&json!({"payload":[]})).is_none());

        let normalized = normalized_server_response(&json!({
            "continuationToken": "opaque",
            "results": {"serverId": "x", "name": "Xbox"},
            "totalItems": 1
        })).unwrap();
        assert_eq!(normalized["results"].as_array().unwrap().len(), 1);
        assert_eq!(normalized["results"][0]["serverId"], "x");
    }
}
