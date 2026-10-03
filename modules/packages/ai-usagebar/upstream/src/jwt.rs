//! Read the claims out of a JWT without verifying it.
//!
//! Two credential readers need the same thing: OpenAI's `auth.json` and
//! Cursor's `state.vscdb` both store an access token whose payload names the
//! account, and both want that name to label the vendor's cache entry. Neither
//! verifies the signature — they are reading a token the local product already
//! obtained and trusts, not authenticating a caller — so this decodes the
//! payload segment and nothing more.
//!
//! Because the claims are unverified, treat what comes out as untrusted input:
//! it labels a cache entry and is sanitized like any other vendor-supplied
//! text before it reaches a UI.

use base64::Engine as _;

/// Decode a JWT's payload segment. `None` for anything that is not three
/// base64url segments wrapping JSON — a malformed token is not an error here,
/// it just means there is no label to be had.
pub fn claims(token: &str) -> Option<serde_json::Value> {
    let mut parts = token.split('.');
    let _header = parts.next()?;
    let payload = parts.next()?;
    // Codex writes unpadded base64url; padded tokens exist in the wild too.
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload)
        .or_else(|_| base64::engine::general_purpose::URL_SAFE.decode(payload))
        .ok()?;
    serde_json::from_slice(&decoded).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn encode(payload: &str) -> String {
        format!(
            "header.{}.signature",
            base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(payload)
        )
    }

    #[test]
    fn reads_the_payload_segment() {
        let token = encode(r#"{"sub":"user-1","email":"a@example.test"}"#);
        let claims = claims(&token).unwrap();
        assert_eq!(claims["sub"], "user-1");
        assert_eq!(claims["email"], "a@example.test");
    }

    #[test]
    fn accepts_a_padded_payload() {
        let padded = format!(
            "header.{}.signature",
            base64::engine::general_purpose::URL_SAFE.encode(r#"{"sub":"user-1"}"#)
        );
        assert_eq!(claims(&padded).unwrap()["sub"], "user-1");
    }

    #[test]
    fn a_malformed_token_is_none_not_a_panic() {
        assert!(claims("").is_none());
        assert!(claims("only-one-segment").is_none());
        assert!(claims("header.@@@not-base64@@@.sig").is_none());
        assert!(claims(&encode("not json at all")).is_none());
    }

    /// The signature is never checked — this reads a token the local product
    /// already holds, so a caller must not treat the claims as authenticated.
    #[test]
    fn the_signature_is_not_verified() {
        let token = encode(r#"{"sub":"user-1"}"#);
        let forged = token.replace(".signature", ".not-the-real-signature");
        assert_eq!(claims(&forged).unwrap()["sub"], "user-1");
    }
}
