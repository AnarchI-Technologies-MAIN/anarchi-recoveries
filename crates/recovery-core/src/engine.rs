use recovery_model::{
    BaselineStatus, EvaluationDecision, EvaluationInput, EvaluationRecord, FactValue,
    NoOpportunityReason, OpportunityDecision, VerificationStatus,
};
use rust_decimal::Decimal;
use thiserror::Error;

use crate::canonical::{CANONICALIZATION_VERSION, decision_hash};
use crate::pricing::calculate_price;

#[derive(Debug, Error)]
pub enum EngineError {
    #[error("organization boundary mismatch")]
    OrganizationBoundaryMismatch,
    #[error("project boundary mismatch")]
    ProjectBoundaryMismatch,
    #[error("baseline must be active")]
    InactiveBaseline,
    #[error("evaluation time is required")]
    MissingEvaluationTime,
    #[error("version is required for {0}")]
    MissingVersion(&'static str),
    #[error("verified fact is missing provenance")]
    MissingFactProvenance,
    #[error("pricing rule version is required")]
    MissingPricingRuleVersion,
    #[error("material cost is required")]
    MissingMaterialCost,
    #[error("equipment cost is required")]
    MissingEquipmentCost,
    #[error("material markup rule is required")]
    MissingMaterialMarkupRule,
    #[error("equipment markup rule is required")]
    MissingEquipmentMarkupRule,
    #[error("tax rule is required")]
    MissingTaxRule,
    #[error("unsupported money scale: {0}")]
    UnsupportedMoneyScale(u32),
    #[error("unsupported rounding rule")]
    UnsupportedRoundingRule,
    #[error("invalid ISO currency: {0}")]
    InvalidCurrency(String),
    #[error("currency mismatch: expected {expected}, got {actual}")]
    CurrencyMismatch { expected: String, actual: String },
    #[error("serialization failed: {0}")]
    Serialization(serde_json::Error),
}

pub fn evaluate_recovery(input: &EvaluationInput) -> Result<EvaluationRecord, EngineError> {
    validate_boundary(input)?;

    let fact = match input.verified_facts.iter().find(|fact| {
        fact.verification_status == VerificationStatus::Verified
            && matches!(fact.value, FactValue::DrawingQuantityDelta(_))
    }) {
        Some(fact) => fact,
        None => {
            return record(EvaluationDecision::NoOpportunity(
                NoOpportunityReason::NoVerifiedDrawingDelta,
            ));
        }
    };

    if fact.evidence.is_empty()
        || fact.verified_by.trim().is_empty()
        || fact.verified_at.trim().is_empty()
        || fact.parser_or_model.version.trim().is_empty()
    {
        return Err(EngineError::MissingFactProvenance);
    }

    let FactValue::DrawingQuantityDelta(delta) = &fact.value;
    if !delta.item_mapping_verified {
        return record(EvaluationDecision::NoOpportunity(
            NoOpportunityReason::ItemMappingUnverified,
        ));
    }
    let quantity_delta = delta.observed_quantity - delta.baseline_quantity;
    if quantity_delta <= Decimal::ZERO {
        return record(EvaluationDecision::NoOpportunity(
            NoOpportunityReason::NonPositiveQuantityDelta,
        ));
    }
    if delta.allowance_remaining > Decimal::ZERO {
        return record(EvaluationDecision::NoOpportunity(
            NoOpportunityReason::AllowanceRemaining,
        ));
    }
    if delta.existing_change_order_coverage {
        return record(EvaluationDecision::NoOpportunity(
            NoOpportunityReason::ExistingChangeOrderCoverage,
        ));
    }
    if !delta.direction_or_performed_work_verified {
        return record(EvaluationDecision::NoOpportunity(
            NoOpportunityReason::DirectionOrPerformedWorkUnverified,
        ));
    }

    let pricing = calculate_price(&input.pricing_inputs, &input.pricing_rules)?;
    let decision = EvaluationDecision::Opportunity(Box::new(OpportunityDecision {
        organization_id: input.organization_id.clone(),
        project_id: input.project_id.clone(),
        baseline_id: input.baseline.baseline_id.clone(),
        evaluation_time: input.evaluation_time.clone(),
        domain_rule_version: input.domain_rules.version.clone(),
        notice_rule_version: input.notice_rules.version.clone(),
        passed_conditions: vec![
            "observed_revision_gt_baseline_revision".to_owned(),
            "item_mapping_verified".to_owned(),
            "quantity_delta_positive".to_owned(),
            "allowance_exhausted".to_owned(),
            "no_existing_change_order_coverage".to_owned(),
            "required_evidence_present".to_owned(),
            "direction_or_performed_work_verified".to_owned(),
        ],
        failed_conditions: Vec::new(),
        missing_conditions: Vec::new(),
        facts_used: vec![fact.fact_id.clone()],
        pricing,
    }));
    record(decision)
}

fn validate_boundary(input: &EvaluationInput) -> Result<(), EngineError> {
    if input.evaluation_time.trim().is_empty() {
        return Err(EngineError::MissingEvaluationTime);
    }
    for (name, version) in [
        ("schema", input.schema_version.as_str()),
        ("domain rules", input.domain_rules.version.as_str()),
        ("notice rules", input.notice_rules.version.as_str()),
    ] {
        if version.trim().is_empty() {
            return Err(EngineError::MissingVersion(name));
        }
    }
    if input.baseline.organization_id != input.organization_id
        || input
            .verified_facts
            .iter()
            .any(|fact| fact.organization_id != input.organization_id)
    {
        return Err(EngineError::OrganizationBoundaryMismatch);
    }
    if input.baseline.project_id != input.project_id
        || input
            .verified_facts
            .iter()
            .any(|fact| fact.project_id != input.project_id)
    {
        return Err(EngineError::ProjectBoundaryMismatch);
    }
    if input.baseline.status != BaselineStatus::Active {
        return Err(EngineError::InactiveBaseline);
    }
    Ok(())
}

fn record(decision: EvaluationDecision) -> Result<EvaluationRecord, EngineError> {
    let evaluation_hash = decision_hash(&decision)?;
    Ok(EvaluationRecord {
        canonicalization: CANONICALIZATION_VERSION.to_owned(),
        decision,
        evaluation_hash,
    })
}
