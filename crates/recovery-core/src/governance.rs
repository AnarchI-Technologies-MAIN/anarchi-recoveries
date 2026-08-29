//! Pure first Recoveries authority gate.
//!
//! This module answers only whether a proposed external notice has the
//! required human approval. It does not execute the notice or emit a durable
//! receipt; those responsibilities remain later, separately receipted steps.

use serde::{Deserialize, Serialize};
use thiserror::Error;

pub const BINDING_ID: &str = "ENF-RECOVERIES-00001";
pub const CANONICAL_RULE_ID: &str = "RULE-AUTH-RECOVERIES-001";
pub const AUTHORITY_CLASS: &str = "TECHNICAL_AUTHORIZATION";
pub const OPERATION: &str = "submit_external_notice";
pub const PURPOSE: &str = "recovery_notice";

#[derive(Debug, Error)]
pub enum GovernanceError {
    #[error("governance request field is required: {0}")]
    MissingField(&'static str),
    #[error("governance operation is not the bound external notice operation")]
    OperationMismatch,
    #[error("governance purpose is not the bound recovery notice purpose")]
    PurposeMismatch,
    #[error("governance request has no payload hash")]
    MissingPayloadHash,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GovernanceRequest {
    pub subject: String,
    pub organization_id: String,
    pub operation: String,
    pub resource: String,
    pub purpose: String,
    pub policy_version: String,
    pub payload_hash: String,
    pub human_approval_id: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum GovernanceResult {
    Allow,
    Deny,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GovernanceDecision {
    pub result: GovernanceResult,
    pub reason_code: String,
    pub binding_id: String,
    pub canonical_rule_id: String,
    pub authority_class: String,
    pub policy_version: String,
    pub organization_id: String,
    pub resource: String,
    pub payload_hash: String,
}

pub fn authorize_external_notice(
    request: &GovernanceRequest,
) -> Result<GovernanceDecision, GovernanceError> {
    validate(request)?;
    let (result, reason_code) = match request.human_approval_id.as_deref() {
        Some(approval_id) if !approval_id.trim().is_empty() => {
            (GovernanceResult::Allow, "HUMAN_APPROVAL_PRESENT")
        }
        _ => (GovernanceResult::Deny, "HUMAN_APPROVAL_REQUIRED"),
    };
    Ok(GovernanceDecision {
        result,
        reason_code: reason_code.to_owned(),
        binding_id: BINDING_ID.to_owned(),
        canonical_rule_id: CANONICAL_RULE_ID.to_owned(),
        authority_class: AUTHORITY_CLASS.to_owned(),
        policy_version: request.policy_version.clone(),
        organization_id: request.organization_id.clone(),
        resource: request.resource.clone(),
        payload_hash: request.payload_hash.clone(),
    })
}

fn validate(request: &GovernanceRequest) -> Result<(), GovernanceError> {
    for (name, value) in [
        ("subject", request.subject.as_str()),
        ("organization_id", request.organization_id.as_str()),
        ("resource", request.resource.as_str()),
        ("policy_version", request.policy_version.as_str()),
    ] {
        if value.trim().is_empty() {
            return Err(GovernanceError::MissingField(name));
        }
    }
    if request.operation != OPERATION {
        return Err(GovernanceError::OperationMismatch);
    }
    if request.purpose != PURPOSE {
        return Err(GovernanceError::PurposeMismatch);
    }
    if request.payload_hash.trim().is_empty() {
        return Err(GovernanceError::MissingPayloadHash);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request() -> GovernanceRequest {
        GovernanceRequest {
            subject: "user-1".to_owned(),
            organization_id: "org-1".to_owned(),
            operation: OPERATION.to_owned(),
            resource: "opportunity-1".to_owned(),
            purpose: PURPOSE.to_owned(),
            policy_version: "RECOVERIES_AUTH_V1".to_owned(),
            payload_hash: "sha256:payload-1".to_owned(),
            human_approval_id: None,
        }
    }

    #[test]
    fn missing_approval_denies() {
        let decision = authorize_external_notice(&request()).unwrap();
        assert_eq!(decision.result, GovernanceResult::Deny);
        assert_eq!(decision.reason_code, "HUMAN_APPROVAL_REQUIRED");
        assert_eq!(decision.binding_id, BINDING_ID);
    }

    #[test]
    fn valid_approval_allows() {
        let mut value = request();
        value.human_approval_id = Some("approval-1".to_owned());
        let decision = authorize_external_notice(&value).unwrap();
        assert_eq!(decision.result, GovernanceResult::Allow);
        assert_eq!(decision.reason_code, "HUMAN_APPROVAL_PRESENT");
    }

    #[test]
    fn wrong_operation_fails_closed() {
        let mut value = request();
        value.operation = "delete_opportunity".to_owned();
        assert!(matches!(
            authorize_external_notice(&value),
            Err(GovernanceError::OperationMismatch)
        ));
    }

    #[test]
    fn missing_payload_hash_fails_closed() {
        let mut value = request();
        value.payload_hash.clear();
        assert!(matches!(
            authorize_external_notice(&value),
            Err(GovernanceError::MissingPayloadHash)
        ));
    }
}
