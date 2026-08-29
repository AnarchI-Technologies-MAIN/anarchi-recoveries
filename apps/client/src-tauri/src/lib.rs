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
}
