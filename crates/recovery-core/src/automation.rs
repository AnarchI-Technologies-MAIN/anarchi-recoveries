use recovery_model::CurrencyCode;
use rust_decimal::{Decimal, RoundingStrategy};
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::canonical::CANONICALIZATION_VERSION;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum AutomationMode {
    DryRun,
    HumanApproval,
    AuthorizedAutomation,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AutomationPolicy {
    pub version: String,
    pub action_type: String,
    pub enabled: bool,
    pub automation_allowed: bool,
    #[serde(with = "rust_decimal::serde::str")]
    pub max_automated_amount: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub minimum_entitlement_strength: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub minimum_evidence_completeness: Decimal,
    pub pricing_required: bool,
    pub recipient_required: bool,
    pub deadline_required: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ActionCandidate {
    pub action_type: String,
    pub currency: CurrencyCode,
    #[serde(with = "rust_decimal::serde::str")]
    pub amount: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub entitlement_strength: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub evidence_completeness: Decimal,
    pub pricing_present: bool,
    pub recipient_present: bool,
    pub deadline_present: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AutomationReceipt {
    pub canonicalization: String,
    pub mode: AutomationMode,
    pub status: AutomationStatus,
    pub reason_codes: Vec<String>,
    pub policy_version: String,
    pub action_type: String,
    pub amount: String,
    pub currency: CurrencyCode,
    pub receipt_hash: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum AutomationStatus {
    SimulationOnly,
    HumanApprovalRequired,
    AuthorizedAutomation,
}

#[derive(Debug, Error)]
pub enum AutomationError {
    #[error("automation policy version and action type are required")]
    MissingPolicyIdentity,
    #[error("candidate action type does not match policy")]
    ActionTypeMismatch,
    #[error("invalid ISO currency: {0}")]
    InvalidCurrency(String),
    #[error("automation values cannot be negative")]
    NegativeValue,
    #[error("automation thresholds must be between zero and one")]
    InvalidThreshold,
    #[error("automation amount exceeds policy maximum")]
    AmountExceedsMaximum,
    #[error("serialization failed: {0}")]
    Serialization(serde_json::Error),
}

pub fn evaluate_action(
    policy: &AutomationPolicy,
    candidate: &ActionCandidate,
    requested_mode: AutomationMode,
) -> Result<AutomationReceipt, AutomationError> {
    validate(policy, candidate)?;
    let mut reasons = Vec::new();
    let status = match requested_mode {
        AutomationMode::DryRun => {
            reasons.push("SIMULATION_ONLY".to_owned());
            AutomationStatus::SimulationOnly
        }
        AutomationMode::HumanApproval => {
            reasons.push("HUMAN_APPROVAL_DEFAULT".to_owned());
            AutomationStatus::HumanApprovalRequired
        }
        AutomationMode::AuthorizedAutomation => {
            if !policy.enabled {
                reasons.push("POLICY_DISABLED".to_owned());
            }
            if !policy.automation_allowed {
                reasons.push("AUTOMATION_NOT_ALLOWED".to_owned());
            }
            if candidate.entitlement_strength < policy.minimum_entitlement_strength {
                reasons.push("ENTITLEMENT_BELOW_THRESHOLD".to_owned());
            }
            if candidate.evidence_completeness < policy.minimum_evidence_completeness {
                reasons.push("EVIDENCE_BELOW_THRESHOLD".to_owned());
            }
            if candidate.amount > policy.max_automated_amount {
                reasons.push("AMOUNT_ABOVE_AUTOMATION_MAX".to_owned());
            }
            if policy.pricing_required && !candidate.pricing_present {
                reasons.push("PRICING_REQUIRED".to_owned());
            }
            if policy.recipient_required && !candidate.recipient_present {
                reasons.push("RECIPIENT_REQUIRED".to_owned());
            }
            if policy.deadline_required && !candidate.deadline_present {
                reasons.push("DEADLINE_REQUIRED".to_owned());
            }
            if reasons.is_empty() {
                AutomationStatus::AuthorizedAutomation
            } else {
                AutomationStatus::HumanApprovalRequired
            }
        }
    };
    let unsigned = UnsignedReceipt {
        canonicalization: CANONICALIZATION_VERSION.to_owned(),
        mode: requested_mode,
        status,
        reason_codes: reasons,
        policy_version: policy.version.clone(),
        action_type: candidate.action_type.clone(),
        amount: canonical_amount(candidate.amount),
        currency: candidate.currency.clone(),
    };
    let receipt_hash = crate::decision_hash(&unsigned).map_err(|error| match error {
        crate::EngineError::Serialization(error) => AutomationError::Serialization(error),
        _ => AutomationError::Serialization(serde_json::Error::io(std::io::Error::other(
            "unexpected canonicalization error",
        ))),
    })?;
    Ok(AutomationReceipt {
        canonicalization: unsigned.canonicalization,
        mode: unsigned.mode,
        status: unsigned.status,
        reason_codes: unsigned.reason_codes,
        policy_version: unsigned.policy_version,
        action_type: unsigned.action_type,
        amount: unsigned.amount,
        currency: unsigned.currency,
        receipt_hash,
    })
}

#[derive(Debug, Serialize)]
struct UnsignedReceipt {
    canonicalization: String,
    mode: AutomationMode,
    status: AutomationStatus,
    reason_codes: Vec<String>,
    policy_version: String,
    action_type: String,
    amount: String,
    currency: CurrencyCode,
}

fn validate(policy: &AutomationPolicy, candidate: &ActionCandidate) -> Result<(), AutomationError> {
    if policy.version.trim().is_empty() || policy.action_type.trim().is_empty() {
        return Err(AutomationError::MissingPolicyIdentity);
    }
    if candidate.action_type != policy.action_type {
        return Err(AutomationError::ActionTypeMismatch);
    }
    if candidate.currency.0.len() != 3
        || !candidate.currency.0.chars().all(|c| c.is_ascii_uppercase())
    {
        return Err(AutomationError::InvalidCurrency(
            candidate.currency.0.clone(),
        ));
    }
    if candidate.amount < Decimal::ZERO
        || policy.max_automated_amount < Decimal::ZERO
        || policy.minimum_entitlement_strength < Decimal::ZERO
        || policy.minimum_evidence_completeness < Decimal::ZERO
    {
        return Err(AutomationError::NegativeValue);
    }
    if policy.minimum_entitlement_strength > Decimal::ONE
        || policy.minimum_evidence_completeness > Decimal::ONE
        || candidate.entitlement_strength < Decimal::ZERO
        || candidate.entitlement_strength > Decimal::ONE
        || candidate.evidence_completeness < Decimal::ZERO
        || candidate.evidence_completeness > Decimal::ONE
    {
        return Err(AutomationError::InvalidThreshold);
    }
    Ok(())
}

fn canonical_amount(value: Decimal) -> String {
    let rounded = value.round_dp_with_strategy(2, RoundingStrategy::MidpointAwayFromZero);
    format!("{rounded:.2}")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn policy() -> AutomationPolicy {
        AutomationPolicy {
            version: "ACTION_POLICY_V1".to_owned(),
            action_type: "SEND_NOTICE".to_owned(),
            enabled: true,
            automation_allowed: true,
            max_automated_amount: "5000.00".parse().unwrap(),
            minimum_entitlement_strength: "0.90".parse().unwrap(),
            minimum_evidence_completeness: "0.95".parse().unwrap(),
            pricing_required: true,
            recipient_required: true,
            deadline_required: true,
        }
    }

    fn candidate() -> ActionCandidate {
        ActionCandidate {
            action_type: "SEND_NOTICE".to_owned(),
            currency: CurrencyCode("USD".to_owned()),
            amount: "4000.00".parse().unwrap(),
            entitlement_strength: "0.95".parse().unwrap(),
            evidence_completeness: "1.00".parse().unwrap(),
            pricing_present: true,
            recipient_present: true,
            deadline_present: true,
        }
    }

    #[test]
    fn dry_run_is_always_simulation_only() {
        let receipt = evaluate_action(&policy(), &candidate(), AutomationMode::DryRun).unwrap();
        assert_eq!(receipt.status, AutomationStatus::SimulationOnly);
        assert_eq!(receipt.reason_codes, vec!["SIMULATION_ONLY"]);
    }

    #[test]
    fn human_approval_is_default_mode() {
        let receipt =
            evaluate_action(&policy(), &candidate(), AutomationMode::HumanApproval).unwrap();
        assert_eq!(receipt.status, AutomationStatus::HumanApprovalRequired);
        assert_eq!(receipt.reason_codes, vec!["HUMAN_APPROVAL_DEFAULT"]);
    }

    #[test]
    fn authorized_automation_requires_every_threshold() {
        let receipt = evaluate_action(
            &policy(),
            &candidate(),
            AutomationMode::AuthorizedAutomation,
        )
        .unwrap();
        assert_eq!(receipt.status, AutomationStatus::AuthorizedAutomation);

        let mut incomplete = candidate();
        incomplete.recipient_present = false;
        let held =
            evaluate_action(&policy(), &incomplete, AutomationMode::AuthorizedAutomation).unwrap();
        assert_eq!(held.status, AutomationStatus::HumanApprovalRequired);
        assert_eq!(held.reason_codes, vec!["RECIPIENT_REQUIRED"]);
    }

    #[test]
    fn disabled_policy_fails_closed_to_human() {
        let mut disabled = policy();
        disabled.enabled = false;
        let receipt = evaluate_action(
            &disabled,
            &candidate(),
            AutomationMode::AuthorizedAutomation,
        )
        .unwrap();
        assert_eq!(receipt.status, AutomationStatus::HumanApprovalRequired);
        assert_eq!(receipt.reason_codes, vec!["POLICY_DISABLED"]);
    }

    #[test]
    fn amount_and_thresholds_fail_closed() {
        let mut over = candidate();
        over.amount = "6000.00".parse().unwrap();
        let receipt =
            evaluate_action(&policy(), &over, AutomationMode::AuthorizedAutomation).unwrap();
        assert_eq!(receipt.reason_codes, vec!["AMOUNT_ABOVE_AUTOMATION_MAX"]);

        let mut invalid = candidate();
        invalid.evidence_completeness = "1.01".parse().unwrap();
        assert!(matches!(
            evaluate_action(&policy(), &invalid, AutomationMode::DryRun),
            Err(AutomationError::InvalidThreshold)
        ));
    }

    #[test]
    fn replay_hash_is_stable() {
        let first = evaluate_action(
            &policy(),
            &candidate(),
            AutomationMode::AuthorizedAutomation,
        )
        .unwrap();
        let second = evaluate_action(
            &policy(),
            &candidate(),
            AutomationMode::AuthorizedAutomation,
        )
        .unwrap();
        assert_eq!(first, second);
    }
}
