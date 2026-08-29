//! Canonical, payload-pinned governance decision receipts.

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::canonical::{CANONICALIZATION_VERSION, decision_hash};
use crate::governance::{GovernanceDecision, GovernanceRequest};

#[derive(Debug, Error)]
pub enum DecisionReceiptError {
    #[error("decision receipt field is required: {0}")]
    MissingField(&'static str),
    #[error("decision receipt scope does not match the governance request")]
    ScopeMismatch,
    #[error("decision receipt payload hash does not match the request")]
    PayloadMismatch,
    #[error("decision receipt binding is not the requested binding")]
    BindingMismatch,
    #[error("decision receipt hash is invalid")]
    InvalidHash,
    #[error("canonical serialization failed: {0}")]
    Serialization(serde_json::Error),
}

impl DecisionReceiptError {
    pub const fn code(&self) -> &'static str {
        match self {
            Self::MissingField(_) => "MISSING_FIELD",
            Self::ScopeMismatch => "SCOPE_MISMATCH",
            Self::PayloadMismatch => "PAYLOAD_MUTATION",
            Self::BindingMismatch => "BINDING_MISMATCH",
            Self::InvalidHash => "INVALID_HASH",
            Self::Serialization(_) => "SERIALIZATION_FAILED",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DecisionReceipt {
    pub canonicalization: String,
    pub decision_id: String,
    pub subject: String,
    pub organization_id: String,
    pub operation: String,
    pub resource: String,
    pub purpose: String,
    pub result: String,
    pub authority_class: String,
    pub policy_version: String,
    pub binding_id: String,
    pub expires_at: String,
    pub payload_hash: String,
    pub decision_hash: String,
}

pub fn issue_decision_receipt(
    request: &GovernanceRequest,
    decision: &GovernanceDecision,
    decision_id: &str,
    purpose: &str,
    expires_at: &str,
) -> Result<DecisionReceipt, DecisionReceiptError> {
    validate_scope(request, decision, decision_id, purpose, expires_at)?;
    let unsigned = UnsignedDecisionReceipt {
        canonicalization: CANONICALIZATION_VERSION.to_owned(),
        decision_id: decision_id.to_owned(),
        subject: request.subject.clone(),
        organization_id: request.organization_id.clone(),
        operation: request.operation.clone(),
        resource: request.resource.clone(),
        purpose: purpose.to_owned(),
        result: result_string(&decision.result),
        authority_class: decision.authority_class.clone(),
        policy_version: request.policy_version.clone(),
        binding_id: decision.binding_id.clone(),
        expires_at: expires_at.to_owned(),
        payload_hash: request.payload_hash.clone(),
    };
    let hash = canonical_hash(&unsigned)?;
    Ok(DecisionReceipt {
        canonicalization: unsigned.canonicalization,
        decision_id: unsigned.decision_id,
        subject: unsigned.subject,
        organization_id: unsigned.organization_id,
        operation: unsigned.operation,
        resource: unsigned.resource,
        purpose: unsigned.purpose,
        result: unsigned.result,
        authority_class: unsigned.authority_class,
        policy_version: unsigned.policy_version,
        binding_id: unsigned.binding_id,
        expires_at: unsigned.expires_at,
        payload_hash: unsigned.payload_hash,
        decision_hash: hash,
    })
}

pub fn verify_decision_receipt(
    receipt: &DecisionReceipt,
    current_payload_hash: &str,
) -> Result<(), DecisionReceiptError> {
    if receipt.payload_hash != current_payload_hash {
        return Err(DecisionReceiptError::PayloadMismatch);
    }
    if receipt.canonicalization != CANONICALIZATION_VERSION {
        return Err(DecisionReceiptError::InvalidHash);
    }
    let unsigned = UnsignedDecisionReceipt {
        canonicalization: receipt.canonicalization.clone(),
        decision_id: receipt.decision_id.clone(),
        subject: receipt.subject.clone(),
        organization_id: receipt.organization_id.clone(),
        operation: receipt.operation.clone(),
        resource: receipt.resource.clone(),
        purpose: receipt.purpose.clone(),
        result: receipt.result.clone(),
        authority_class: receipt.authority_class.clone(),
        policy_version: receipt.policy_version.clone(),
        binding_id: receipt.binding_id.clone(),
        expires_at: receipt.expires_at.clone(),
        payload_hash: receipt.payload_hash.clone(),
    };
    if canonical_hash(&unsigned)? != receipt.decision_hash {
        return Err(DecisionReceiptError::InvalidHash);
    }
    Ok(())
}

#[derive(Debug, Serialize)]
struct UnsignedDecisionReceipt {
    canonicalization: String,
    decision_id: String,
    subject: String,
    organization_id: String,
    operation: String,
    resource: String,
    purpose: String,
    result: String,
    authority_class: String,
    policy_version: String,
    binding_id: String,
    expires_at: String,
    payload_hash: String,
}

fn canonical_hash(value: &UnsignedDecisionReceipt) -> Result<String, DecisionReceiptError> {
    decision_hash(value).map_err(|error| match error {
        crate::EngineError::Serialization(error) => DecisionReceiptError::Serialization(error),
        _ => DecisionReceiptError::Serialization(serde_json::Error::io(std::io::Error::other(
            "unexpected canonicalization error",
        ))),
    })
}

fn validate_scope(
    request: &GovernanceRequest,
    decision: &GovernanceDecision,
    decision_id: &str,
    purpose: &str,
    expires_at: &str,
) -> Result<(), DecisionReceiptError> {
    for (name, value) in [
        ("decision_id", decision_id),
        ("purpose", purpose),
        ("expires_at", expires_at),
    ] {
        if value.trim().is_empty() {
            return Err(DecisionReceiptError::MissingField(name));
        }
    }
    if request.organization_id != decision.organization_id
        || request.resource != decision.resource
        || request.payload_hash != decision.payload_hash
        || request.policy_version != decision.policy_version
    {
        return Err(DecisionReceiptError::ScopeMismatch);
    }
    if request.purpose != purpose {
        return Err(DecisionReceiptError::ScopeMismatch);
    }
    if decision.binding_id.trim().is_empty() {
        return Err(DecisionReceiptError::BindingMismatch);
    }
    Ok(())
}

fn result_string(result: &crate::governance::GovernanceResult) -> String {
    match result {
        crate::governance::GovernanceResult::Allow => "ALLOW".to_owned(),
        crate::governance::GovernanceResult::Deny => "DENY".to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::governance::{OPERATION, PURPOSE, authorize_external_notice};

    fn request() -> GovernanceRequest {
        GovernanceRequest {
            subject: "user-1".to_owned(),
            organization_id: "org-1".to_owned(),
            operation: OPERATION.to_owned(),
            resource: "opportunity-1".to_owned(),
            purpose: PURPOSE.to_owned(),
            policy_version: "RECOVERIES_AUTH_V1".to_owned(),
            payload_hash: "sha256:payload-1".to_owned(),
            human_approval_id: Some("approval-1".to_owned()),
        }
    }

    #[test]
    fn receipt_is_replayable() {
        let value = request();
        let decision = authorize_external_notice(&value).unwrap();
        let first = issue_decision_receipt(
            &value,
            &decision,
            "decision-1",
            PURPOSE,
            "2026-08-30T00:00:00Z",
        )
        .unwrap();
        let second = issue_decision_receipt(
            &value,
            &decision,
            "decision-1",
            PURPOSE,
            "2026-08-30T00:00:00Z",
        )
        .unwrap();
        assert_eq!(first, second);
        verify_decision_receipt(&first, "sha256:payload-1").unwrap();
    }

    #[test]
    fn payload_mutation_is_rejected() {
        let value = request();
        let decision = authorize_external_notice(&value).unwrap();
        let receipt = issue_decision_receipt(
            &value,
            &decision,
            "decision-1",
            PURPOSE,
            "2026-08-30T00:00:00Z",
        )
        .unwrap();
        assert!(matches!(
            verify_decision_receipt(&receipt, "sha256:mutated"),
            Err(DecisionReceiptError::PayloadMismatch)
        ));
    }

    #[test]
    fn tampered_hash_is_rejected() {
        let value = request();
        let decision = authorize_external_notice(&value).unwrap();
        let mut receipt = issue_decision_receipt(
            &value,
            &decision,
            "decision-1",
            PURPOSE,
            "2026-08-30T00:00:00Z",
        )
        .unwrap();
        receipt.resource = "other-opportunity".to_owned();
        assert!(matches!(
            verify_decision_receipt(&receipt, "sha256:payload-1"),
            Err(DecisionReceiptError::InvalidHash)
        ));
    }
}
