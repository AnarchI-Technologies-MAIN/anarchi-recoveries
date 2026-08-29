use serde::{Deserialize, Serialize};
use thiserror::Error;

pub const PRODUCT_NAME: &str = "ANARCHI / RECOVERIES";
pub const WINDOWS_BINARY_NAME: &str = "AnarchI-Recoveries-x64.exe";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClientMode {
    Online,
    Offline,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum NotificationTarget {
    WindowsDesktop,
    Ios,
    Android,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum NotificationPrivacy {
    Private,
    Detailed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationPayload {
    pub target: NotificationTarget,
    pub privacy: NotificationPrivacy,
    pub title: String,
    pub body: String,
    pub lock_screen_safe: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CacheKind {
    RecentOpportunitySummary,
    PreviouslyOpenedEvidence,
    Deadline,
    ProjectMetadata,
    DraftComment,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CachedItem {
    pub kind: CacheKind,
    pub item_id: String,
    pub organization_id: String,
    pub captured_at: String,
    pub expires_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EncryptedCacheEntry {
    pub kind: CacheKind,
    pub item_id: String,
    pub organization_id: String,
    pub ciphertext: Vec<u8>,
    pub key_handle: String,
    pub captured_at: String,
    pub expires_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClientStatus {
    pub mode: ClientMode,
    pub last_sync: Option<String>,
    pub core_version: String,
    pub evaluation_version: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OfflineApproval {
    pub recovery_id: String,
    pub organization_id: String,
    pub payload_hash: String,
    pub queued_at: String,
    pub state: OfflineApprovalState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OfflineApprovalState {
    Queued,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReconnectValidation {
    pub opportunity_valid: bool,
    pub payload_hash_valid: bool,
    pub policy_valid: bool,
    pub deadline_valid: bool,
    pub authority_valid: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ReconnectOutcome {
    ReadyToExecute,
    Rejected { failed_checks: Vec<String> },
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ClientShellError {
    #[error("{0} is required")]
    Required(&'static str),
    #[error("offline approval can only be queued, never executed")]
    OfflineExecutionForbidden,
    #[error("encrypted cache entry is invalid: {0}")]
    InvalidEncryptedCache(&'static str),
    #[error("notification field {0} is required")]
    InvalidNotification(&'static str),
}

pub fn build_notification(
    target: NotificationTarget,
    privacy: NotificationPrivacy,
    summary: &str,
    confidential_detail: Option<&str>,
) -> Result<NotificationPayload, ClientShellError> {
    if summary.trim().is_empty() {
        return Err(ClientShellError::InvalidNotification("summary"));
    }
    let (body, lock_screen_safe) = match privacy {
        NotificationPrivacy::Private => ("AnarchI Recoveries update available".to_owned(), true),
        NotificationPrivacy::Detailed => {
            let detail = confidential_detail
                .filter(|value| !value.trim().is_empty())
                .ok_or(ClientShellError::InvalidNotification("confidential_detail"))?;
            (format!("{summary}: {detail}"), false)
        }
    };
    Ok(NotificationPayload {
        target,
        privacy,
        title: "ANARCHI / RECOVERIES".to_owned(),
        body,
        lock_screen_safe,
    })
}

pub fn validate_encrypted_cache_entry(
    entry: &EncryptedCacheEntry,
    observed_at: &str,
) -> Result<(), ClientShellError> {
    let observed_owned = observed_at.to_owned();
    for (value, field) in [
        (&entry.item_id, "item_id"),
        (&entry.organization_id, "organization_id"),
        (&entry.key_handle, "key_handle"),
        (&entry.captured_at, "captured_at"),
        (&entry.expires_at, "expires_at"),
        (&observed_owned, "observed_at"),
    ] {
        if value.trim().is_empty() {
            return Err(ClientShellError::InvalidEncryptedCache(field));
        }
    }
    if entry.ciphertext.is_empty() {
        return Err(ClientShellError::InvalidEncryptedCache("ciphertext"));
    }
    if entry.expires_at <= entry.captured_at {
        return Err(ClientShellError::InvalidEncryptedCache(
            "expiry must be after capture",
        ));
    }
    if observed_at >= entry.expires_at.as_str() {
        return Err(ClientShellError::InvalidEncryptedCache(
            "cache entry expired",
        ));
    }
    Ok(())
}

pub fn queue_offline_approval(
    recovery_id: &str,
    organization_id: &str,
    payload_hash: &str,
    queued_at: &str,
) -> Result<OfflineApproval, ClientShellError> {
    for (value, field) in [
        (recovery_id, "recovery_id"),
        (organization_id, "organization_id"),
        (payload_hash, "payload_hash"),
        (queued_at, "queued_at"),
    ] {
        if value.trim().is_empty() {
            return Err(ClientShellError::Required(field));
        }
    }
    Ok(OfflineApproval {
        recovery_id: recovery_id.to_owned(),
        organization_id: organization_id.to_owned(),
        payload_hash: payload_hash.to_owned(),
        queued_at: queued_at.to_owned(),
        state: OfflineApprovalState::Queued,
    })
}

pub fn validate_on_reconnect(checks: &ReconnectValidation) -> ReconnectOutcome {
    let mut failed_checks = Vec::new();
    if !checks.opportunity_valid {
        failed_checks.push("opportunity".to_owned());
    }
    if !checks.payload_hash_valid {
        failed_checks.push("payload_hash".to_owned());
    }
    if !checks.policy_valid {
        failed_checks.push("policy".to_owned());
    }
    if !checks.deadline_valid {
        failed_checks.push("deadline".to_owned());
    }
    if !checks.authority_valid {
        failed_checks.push("authority".to_owned());
    }
    if failed_checks.is_empty() {
        ReconnectOutcome::ReadyToExecute
    } else {
        ReconnectOutcome::Rejected { failed_checks }
    }
}

pub fn assert_offline_execution_forbidden(mode: ClientMode) -> Result<(), ClientShellError> {
    if mode == ClientMode::Offline {
        return Err(ClientShellError::OfflineExecutionForbidden);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn offline_approval_is_queued_not_executed() {
        let approval = queue_offline_approval(
            "REC / 00481",
            "org-1",
            "a".repeat(64).as_str(),
            "2026-08-29T12:00:00Z",
        )
        .expect("valid queue");
        assert_eq!(approval.state, OfflineApprovalState::Queued);
        assert_eq!(
            assert_offline_execution_forbidden(ClientMode::Offline),
            Err(ClientShellError::OfflineExecutionForbidden)
        );
    }

    #[test]
    fn reconnect_requires_every_revalidation() {
        let checks = ReconnectValidation {
            opportunity_valid: true,
            payload_hash_valid: true,
            policy_valid: true,
            deadline_valid: true,
            authority_valid: true,
        };
        assert_eq!(
            validate_on_reconnect(&checks),
            ReconnectOutcome::ReadyToExecute
        );
        let mut failed = checks;
        failed.payload_hash_valid = false;
        assert_eq!(
            validate_on_reconnect(&failed),
            ReconnectOutcome::Rejected {
                failed_checks: vec!["payload_hash".to_owned()]
            }
        );
    }

    #[test]
    fn missing_identity_fails_closed() {
        assert_eq!(
            queue_offline_approval("", "org-1", "hash", "time"),
            Err(ClientShellError::Required("recovery_id"))
        );
    }

    #[test]
    fn cache_requires_opaque_ciphertext_and_expiry() {
        let entry = EncryptedCacheEntry {
            kind: CacheKind::PreviouslyOpenedEvidence,
            item_id: "evidence-1".to_owned(),
            organization_id: "org-1".to_owned(),
            ciphertext: vec![1, 2, 3],
            key_handle: "windows-dpapi:cache-1".to_owned(),
            captured_at: "2026-08-29T12:00:00Z".to_owned(),
            expires_at: "2026-08-30T12:00:00Z".to_owned(),
        };
        assert!(validate_encrypted_cache_entry(&entry, "2026-08-29T12:01:00Z").is_ok());
        assert_eq!(
            validate_encrypted_cache_entry(&entry, "2026-08-31T00:00:00Z"),
            Err(ClientShellError::InvalidEncryptedCache(
                "cache entry expired"
            ))
        );
        let empty = EncryptedCacheEntry {
            ciphertext: Vec::new(),
            ..entry
        };
        assert_eq!(
            validate_encrypted_cache_entry(&empty, "2026-08-29T12:01:00Z"),
            Err(ClientShellError::InvalidEncryptedCache("ciphertext"))
        );
    }

    #[test]
    fn private_notifications_never_place_detail_on_lock_screen() {
        let notification = build_notification(
            NotificationTarget::WindowsDesktop,
            NotificationPrivacy::Private,
            "Deadline approaching",
            Some("REC / 00481: $12,481.23"),
        )
        .expect("valid notification");
        assert!(notification.lock_screen_safe);
        assert_eq!(notification.body, "AnarchI Recoveries update available");
        assert!(!notification.body.contains("12,481"));
    }

    #[test]
    fn detailed_notifications_are_explicitly_opt_in() {
        let notification = build_notification(
            NotificationTarget::Ios,
            NotificationPrivacy::Detailed,
            "Deadline approaching",
            Some("REC / 00481"),
        )
        .expect("valid notification");
        assert!(!notification.lock_screen_safe);
        assert!(notification.body.contains("REC / 00481"));
        assert_eq!(
            build_notification(
                NotificationTarget::Android,
                NotificationPrivacy::Detailed,
                "Update",
                None
            ),
            Err(ClientShellError::InvalidNotification("confidential_detail"))
        );
    }
}
