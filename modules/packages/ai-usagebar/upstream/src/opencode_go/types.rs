//! OpenCode Go usage response types and schema validation.

use chrono::{DateTime, Utc};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq)]
pub struct Window {
    pub status: String,
    pub percent: f64,
    pub resets_at: DateTime<Utc>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Usage {
    pub rolling: Option<Window>,
    pub weekly: Option<Window>,
    pub monthly: Option<Window>,
}

impl Eq for Usage {}

pub fn parse_usage(value: &Value) -> Result<Usage, String> {
    let root = value
        .as_object()
        .ok_or_else(|| "OpenCode Go response must be a JSON object".to_string())?;
    if root.contains_key("error") {
        return Err("OpenCode Go response is an error envelope".to_string());
    }
    let usage = root
        .get("usage")
        .ok_or_else(|| "OpenCode Go response missing top-level usage".to_string())?
        .as_object()
        .ok_or_else(|| "OpenCode Go response usage must be an object".to_string())?;

    let parsed = Usage {
        rolling: parse_optional_window(usage, "rolling")?,
        weekly: parse_optional_window(usage, "weekly")?,
        monthly: parse_optional_window(usage, "monthly")?,
    };
    if parsed.rolling.is_none() && parsed.weekly.is_none() && parsed.monthly.is_none() {
        return Err("OpenCode Go response has no supported usage windows".to_string());
    }
    Ok(parsed)
}

fn parse_optional_window(
    usage: &serde_json::Map<String, Value>,
    name: &str,
) -> Result<Option<Window>, String> {
    usage
        .get(name)
        .map(|value| parse_window(value, name))
        .transpose()
}

fn parse_window(value: &Value, name: &str) -> Result<Window, String> {
    let object = value
        .as_object()
        .ok_or_else(|| format!("usage.{name} must be an object"))?;
    let status = object
        .get("status")
        .and_then(Value::as_str)
        .ok_or_else(|| format!("usage.{name}.status must be a string"))?
        .to_string();
    if !matches!(status.as_str(), "ok" | "rate-limited") {
        return Err(format!("usage.{name}.status is unsupported"));
    }
    let percent = object
        .get("percent")
        .and_then(Value::as_f64)
        .ok_or_else(|| format!("usage.{name}.percent must be a number"))?;
    if !percent.is_finite() || !(0.0..=100.0).contains(&percent) {
        return Err(format!(
            "usage.{name}.percent must be finite and between 0 and 100"
        ));
    }
    let resets_at = object
        .get("resetsAt")
        .and_then(Value::as_str)
        .ok_or_else(|| format!("usage.{name}.resetsAt must be an RFC3339 timestamp"))?
        .parse::<DateTime<chrono::FixedOffset>>()
        .map_err(|error| format!("usage.{name}.resetsAt is not RFC3339: {error}"))?
        .with_timezone(&Utc);

    Ok(Window {
        status,
        percent,
        resets_at,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn window(percent: Value) -> Value {
        serde_json::json!({
            "status": "ok",
            "percent": percent,
            "resetsAt": "2026-08-16T20:00:00Z"
        })
    }

    #[test]
    fn parses_required_window_fields_and_ignores_additive_fields() {
        let value = serde_json::json!({
            "usage": {
                "rolling": {
                    "status": "ok",
                    "percent": 12.3,
                    "resetsAt": "2026-08-16T20:00:00Z",
                    "future": {"ignored": true}
                }
            },
            "future_envelope_field": true
        });

        let parsed = parse_usage(&value).expect("usage should parse");
        let rolling = parsed.rolling.expect("rolling window");
        assert_eq!(rolling.status, "ok");
        assert_eq!(rolling.percent, 12.3);
        assert_eq!(
            rolling.resets_at,
            "2026-08-16T20:00:00Z".parse::<DateTime<Utc>>().unwrap()
        );
        assert!(parsed.weekly.is_none());
        assert!(parsed.monthly.is_none());
    }

    #[test]
    fn rejects_missing_usage_and_error_envelopes() {
        for value in [
            serde_json::json!({}),
            serde_json::json!({"error": "unauthorized"}),
            serde_json::json!({
                "error": "unauthorized",
                "usage": {"rolling": window(serde_json::json!(1))}
            }),
            serde_json::json!({"usage": null}),
            serde_json::json!({"usage": {}}),
        ] {
            assert!(
                parse_usage(&value).is_err(),
                "unexpectedly accepted {value}"
            );
        }
    }

    #[test]
    fn rejects_obsolete_usage_percent_field() {
        let value = serde_json::json!({
            "usage": {
                "rolling": {
                    "status": "ok",
                    "usagePercent": 12.3,
                    "resetsAt": "2026-08-16T20:00:00Z"
                }
            }
        });
        assert!(parse_usage(&value).is_err());
    }

    #[test]
    fn rejects_non_finite_or_out_of_range_percent() {
        for percent in [
            serde_json::json!(-0.1),
            serde_json::json!(100.1),
            serde_json::json!("NaN"),
            serde_json::json!(null),
        ] {
            let value = serde_json::json!({"usage": {"rolling": window(percent)}});
            assert!(
                parse_usage(&value).is_err(),
                "unexpectedly accepted {value}"
            );
        }
    }

    #[test]
    fn rejects_invalid_timestamp_and_window_shape() {
        let invalid_timestamp = serde_json::json!({
            "usage": {
                "rolling": {
                    "status": "ok",
                    "percent": 1,
                    "resetsAt": "tomorrow"
                }
            }
        });
        assert!(parse_usage(&invalid_timestamp).is_err());

        let invalid_window = serde_json::json!({"usage": {"weekly": "not-an-object"}});
        assert!(parse_usage(&invalid_window).is_err());

        let invalid_status = serde_json::json!({
            "usage": {
                "rolling": {
                    "status": "limited",
                    "percent": 1,
                    "resetsAt": "2026-08-16T20:00:00Z"
                }
            }
        });
        assert!(parse_usage(&invalid_status).is_err());
    }
}
