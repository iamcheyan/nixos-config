//! Deserializers shared by the OAuth credential readers.
//!
//! Both `~/.claude/.credentials.json` and `~/.codex/auth.json` are written by
//! another product, and both can hold a token field that is present but blank.
//! An empty access token is not a credential — it produces a request that gets
//! a 401 the user cannot act on — so it is rejected at parse time rather than
//! carried into a fetch. The rule is the same for both readers and lives here
//! once so it cannot come to mean two things.

use serde::Deserialize as _;

/// A required token field: present, and not blank once trimmed.
pub fn de_nonempty_string<'de, D>(d: D) -> std::result::Result<String, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let value = String::deserialize(d)?;
    if value.trim().is_empty() {
        Err(serde::de::Error::custom("token cannot be empty"))
    } else {
        Ok(value)
    }
}

/// [`de_nonempty_string`] for an optional field. Absent is fine; present and
/// blank is not — that is a written-out empty string, not an absent one.
pub fn de_opt_nonempty_string<'de, D>(d: D) -> std::result::Result<Option<String>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    Option::<String>::deserialize(d)?
        .map(|value| {
            if value.trim().is_empty() {
                Err(serde::de::Error::custom("token cannot be empty"))
            } else {
                Ok(value)
            }
        })
        .transpose()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, serde::Deserialize)]
    struct Probe {
        #[serde(deserialize_with = "de_nonempty_string")]
        required: String,
        #[serde(default, deserialize_with = "de_opt_nonempty_string")]
        optional: Option<String>,
    }

    fn parse(json: &str) -> Result<Probe, serde_json::Error> {
        serde_json::from_str(json)
    }

    #[test]
    fn a_present_token_survives() {
        let p = parse(r#"{"required":"tok","optional":"opt"}"#).unwrap();
        assert_eq!(p.required, "tok");
        assert_eq!(p.optional.as_deref(), Some("opt"));
    }

    #[test]
    fn an_absent_optional_is_none_not_an_error() {
        assert!(parse(r#"{"required":"tok"}"#).unwrap().optional.is_none());
    }

    #[test]
    fn a_blank_token_is_rejected_in_either_position() {
        for json in [
            r#"{"required":""}"#,
            r#"{"required":"   "}"#,
            r#"{"required":"tok","optional":""}"#,
            r#"{"required":"tok","optional":"\t"}"#,
        ] {
            let err = parse(json).unwrap_err();
            assert!(
                err.to_string().contains("token cannot be empty"),
                "{json} -> {err}"
            );
        }
    }
}
