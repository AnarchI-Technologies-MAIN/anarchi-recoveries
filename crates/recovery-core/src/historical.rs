//! Deterministic, read-only historical rescue scanning.
//!
//! The scanner consumes already-normalized historical records. It does not
//! ingest files, call connectors, infer facts, calculate prices, or mutate
//! recovery state. Its only authority is to classify each record for review
//! and emit a replayable scan receipt.

use recovery_model::VerificationStatus;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::canonical::{CANONICALIZATION_VERSION, decision_hash};

const CONDITION_REVISION_DELTA: &str = "observed_revision_gt_baseline_revision";
const CONDITION_ITEM_MAPPING: &str = "item_mapping_verified";
const CONDITION_QUANTITY_DELTA: &str = "quantity_delta_positive";
const CONDITION_ALLOWANCE: &str = "allowance_exhausted";
const CONDITION_CHANGE_ORDER: &str = "no_existing_change_order_coverage";
const CONDITION_BASELINE_EVIDENCE: &str = "required_baseline_evidence_present";
const CONDITION_REVISED_EVIDENCE: &str = "required_revised_evidence_present";
const CONDITION_DIRECTION: &str = "direction_or_performed_work_verified";
const CONDITION_VERIFICATION: &str = "record_verified";

#[derive(Debug, Error)]
pub enum HistoricalRescueError {
    #[error("historical scan identity is required")]
    MissingScanIdentity,
    #[error("historical scan rule version is required")]
    MissingRuleVersion,
    #[error("historical scan must contain at least one record")]
    EmptyScan,
    #[error("record {0} has an invalid identity field")]
    MissingRecordIdentity(String),
    #[error("record {record_id} crosses the organization boundary")]
    OrganizationBoundaryMismatch { record_id: String },
    #[error("record {record_id} crosses the project boundary")]
    ProjectBoundaryMismatch { record_id: String },
    #[error("record {0} has an invalid quantity")]
    InvalidQuantity(String),
    #[error("record {0} has an invalid revision order")]
    InvalidRevisionOrder(String),
    #[error("canonical serialization failed: {0}")]
    Serialization(serde_json::Error),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HistoricalScanInput {
    pub schema_version: String,
    pub scan_id: String,
    pub organization_id: String,
    pub project_id: String,
    pub rule_version: String,
    pub evaluation_time: String,
    pub records: Vec<HistoricalRecord>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HistoricalRecord {
    pub record_id: String,
    pub organization_id: String,
    pub project_id: String,
    pub scope_item_id: String,
    pub location: String,
    pub change_type: String,
    pub origin_revision_or_directive: String,
    pub time_bucket: String,
    pub baseline_revision: String,
    pub observed_revision: String,
    pub baseline_revision_order: i64,
    pub observed_revision_order: i64,
    #[serde(with = "rust_decimal::serde::str")]
    pub baseline_quantity: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub observed_quantity: Decimal,
    pub unit: String,
    pub item_mapping_verified: bool,
    pub allowance_remaining: Decimal,
    pub existing_change_order_coverage: bool,
    pub required_baseline_evidence_present: bool,
    pub required_revised_evidence_present: bool,
    pub direction_or_performed_work_verified: bool,
    pub verification_status: VerificationStatus,
    pub source_evidence_ids: Vec<String>,
    pub source_version: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HistoricalScanResult {
    pub canonicalization: String,
    pub schema_version: String,
    pub scan_id: String,
    pub organization_id: String,
    pub project_id: String,
    pub rule_version: String,
    pub evaluation_time: String,
    pub findings: Vec<HistoricalFinding>,
    pub scan_hash: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HistoricalFinding {
    pub record_id: String,
    pub deduplication_key: HistoricalDeduplicationKey,
    pub decision: HistoricalDecision,
    pub passed_conditions: Vec<String>,
    pub failed_conditions: Vec<String>,
    pub missing_conditions: Vec<String>,
    pub facts_used: Vec<String>,
    pub source_evidence_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct HistoricalDeduplicationKey {
    pub project: String,
    pub scope_item: String,
    pub location: String,
    pub change_type: String,
    pub origin_revision_or_directive: String,
    pub time_bucket: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum HistoricalDecision {
    EligibleForReview,
    PotentialChange,
    MoreEvidenceRequired,
    NoOpportunity,
    Duplicate,
}

pub fn scan_historical(
    mut input: HistoricalScanInput,
) -> Result<HistoricalScanResult, HistoricalRescueError> {
    validate_scan(&input)?;
    input.records.sort_by(|left, right| {
        deduplication_key(left)
            .cmp(&deduplication_key(right))
            .then_with(|| left.record_id.cmp(&right.record_id))
    });

    let mut findings = Vec::with_capacity(input.records.len());
    let mut previous_key: Option<HistoricalDeduplicationKey> = None;
    for record in &input.records {
        let key = deduplication_key(record);
        if previous_key.as_ref() == Some(&key) {
            findings.push(HistoricalFinding {
                record_id: record.record_id.clone(),
                deduplication_key: key,
                decision: HistoricalDecision::Duplicate,
                passed_conditions: Vec::new(),
                failed_conditions: vec!["duplicate_deduplication_key".to_owned()],
                missing_conditions: Vec::new(),
                facts_used: vec![record.record_id.clone()],
                source_evidence_ids: sorted_evidence_ids(record),
            });
            continue;
        }
        previous_key = Some(key.clone());
        findings.push(classify_record(record, key));
    }

    let unsigned = UnsignedScanResult {
        canonicalization: CANONICALIZATION_VERSION.to_owned(),
        schema_version: input.schema_version.clone(),
        scan_id: input.scan_id.clone(),
        organization_id: input.organization_id.clone(),
        project_id: input.project_id.clone(),
        rule_version: input.rule_version.clone(),
        evaluation_time: input.evaluation_time.clone(),
        findings: findings.clone(),
    };
    let scan_hash = decision_hash(&unsigned).map_err(|error| match error {
        crate::EngineError::Serialization(error) => HistoricalRescueError::Serialization(error),
        _ => HistoricalRescueError::Serialization(serde_json::Error::io(std::io::Error::other(
            "unexpected canonicalization error",
        ))),
    })?;

    Ok(HistoricalScanResult {
        canonicalization: unsigned.canonicalization,
        schema_version: unsigned.schema_version,
        scan_id: unsigned.scan_id,
        organization_id: unsigned.organization_id,
        project_id: unsigned.project_id,
        rule_version: unsigned.rule_version,
        evaluation_time: unsigned.evaluation_time,
        findings: unsigned.findings,
        scan_hash,
    })
}

#[derive(Debug, Serialize)]
struct UnsignedScanResult {
    canonicalization: String,
    schema_version: String,
    scan_id: String,
    organization_id: String,
    project_id: String,
    rule_version: String,
    evaluation_time: String,
    findings: Vec<HistoricalFinding>,
}

fn validate_scan(input: &HistoricalScanInput) -> Result<(), HistoricalRescueError> {
    if input.schema_version.trim().is_empty()
        || input.scan_id.trim().is_empty()
        || input.organization_id.trim().is_empty()
        || input.project_id.trim().is_empty()
        || input.evaluation_time.trim().is_empty()
    {
        return Err(HistoricalRescueError::MissingScanIdentity);
    }
    if input.rule_version.trim().is_empty() {
        return Err(HistoricalRescueError::MissingRuleVersion);
    }
    if input.records.is_empty() {
        return Err(HistoricalRescueError::EmptyScan);
    }
    for record in &input.records {
        if record.record_id.trim().is_empty()
            || record.scope_item_id.trim().is_empty()
            || record.location.trim().is_empty()
            || record.change_type.trim().is_empty()
            || record.origin_revision_or_directive.trim().is_empty()
            || record.time_bucket.trim().is_empty()
            || record.unit.trim().is_empty()
        {
            return Err(HistoricalRescueError::MissingRecordIdentity(
                record.record_id.clone(),
            ));
        }
        if record.organization_id != input.organization_id {
            return Err(HistoricalRescueError::OrganizationBoundaryMismatch {
                record_id: record.record_id.clone(),
            });
        }
        if record.project_id != input.project_id {
            return Err(HistoricalRescueError::ProjectBoundaryMismatch {
                record_id: record.record_id.clone(),
            });
        }
        if record.baseline_quantity < Decimal::ZERO || record.observed_quantity < Decimal::ZERO {
            return Err(HistoricalRescueError::InvalidQuantity(
                record.record_id.clone(),
            ));
        }
        if record.baseline_revision_order < 0 || record.observed_revision_order < 0 {
            return Err(HistoricalRescueError::InvalidRevisionOrder(
                record.record_id.clone(),
            ));
        }
    }
    Ok(())
}

fn deduplication_key(record: &HistoricalRecord) -> HistoricalDeduplicationKey {
    HistoricalDeduplicationKey {
        project: record.project_id.clone(),
        scope_item: record.scope_item_id.clone(),
        location: record.location.clone(),
        change_type: record.change_type.clone(),
        origin_revision_or_directive: record.origin_revision_or_directive.clone(),
        time_bucket: record.time_bucket.clone(),
    }
}

fn classify_record(
    record: &HistoricalRecord,
    key: HistoricalDeduplicationKey,
) -> HistoricalFinding {
    let mut passed = Vec::new();
    let mut failed = Vec::new();
    let mut missing = Vec::new();
    let evidence_ids = sorted_evidence_ids(record);

    if record.observed_revision_order > record.baseline_revision_order {
        passed.push(CONDITION_REVISION_DELTA.to_owned());
    } else {
        failed.push(CONDITION_REVISION_DELTA.to_owned());
    }

    let quantity_delta = record.observed_quantity - record.baseline_quantity;
    if quantity_delta > Decimal::ZERO {
        passed.push(CONDITION_QUANTITY_DELTA.to_owned());
    } else {
        failed.push(CONDITION_QUANTITY_DELTA.to_owned());
    }

    if record.item_mapping_verified {
        passed.push(CONDITION_ITEM_MAPPING.to_owned());
    } else {
        missing.push(CONDITION_ITEM_MAPPING.to_owned());
    }
    if record.allowance_remaining <= Decimal::ZERO {
        passed.push(CONDITION_ALLOWANCE.to_owned());
    } else {
        failed.push(CONDITION_ALLOWANCE.to_owned());
    }
    if !record.existing_change_order_coverage {
        passed.push(CONDITION_CHANGE_ORDER.to_owned());
    } else {
        failed.push(CONDITION_CHANGE_ORDER.to_owned());
    }
    if record.required_baseline_evidence_present {
        passed.push(CONDITION_BASELINE_EVIDENCE.to_owned());
    } else {
        missing.push(CONDITION_BASELINE_EVIDENCE.to_owned());
    }
    if record.required_revised_evidence_present {
        passed.push(CONDITION_REVISED_EVIDENCE.to_owned());
    } else {
        missing.push(CONDITION_REVISED_EVIDENCE.to_owned());
    }
    if record.direction_or_performed_work_verified {
        passed.push(CONDITION_DIRECTION.to_owned());
    } else {
        missing.push(CONDITION_DIRECTION.to_owned());
    }
    if record.verification_status == VerificationStatus::Verified {
        passed.push(CONDITION_VERIFICATION.to_owned());
    } else {
        missing.push(CONDITION_VERIFICATION.to_owned());
    }
    if evidence_ids.is_empty() || record.source_version.trim().is_empty() {
        missing.push("source_provenance".to_owned());
    }

    let decision = if !failed.is_empty()
        && (failed.contains(&CONDITION_QUANTITY_DELTA.to_owned())
            || failed.contains(&CONDITION_ALLOWANCE.to_owned())
            || failed.contains(&CONDITION_CHANGE_ORDER.to_owned())
            || failed.contains(&CONDITION_REVISION_DELTA.to_owned()))
    {
        HistoricalDecision::NoOpportunity
    } else if !missing.is_empty() {
        if missing.contains(&CONDITION_DIRECTION.to_owned())
            && missing.len() == 1
            && evidence_is_complete(record, &evidence_ids)
        {
            HistoricalDecision::PotentialChange
        } else {
            HistoricalDecision::MoreEvidenceRequired
        }
    } else {
        HistoricalDecision::EligibleForReview
    };

    HistoricalFinding {
        record_id: record.record_id.clone(),
        deduplication_key: key,
        decision,
        passed_conditions: passed,
        failed_conditions: failed,
        missing_conditions: missing,
        facts_used: vec![record.record_id.clone()],
        source_evidence_ids: evidence_ids,
    }
}

fn evidence_is_complete(record: &HistoricalRecord, evidence_ids: &[String]) -> bool {
    record.item_mapping_verified
        && record.required_baseline_evidence_present
        && record.required_revised_evidence_present
        && record.verification_status == VerificationStatus::Verified
        && !evidence_ids.is_empty()
        && !record.source_version.trim().is_empty()
}

fn sorted_evidence_ids(record: &HistoricalRecord) -> Vec<String> {
    let mut evidence_ids = record.source_evidence_ids.clone();
    evidence_ids.sort();
    evidence_ids.dedup();
    evidence_ids
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(id: &str) -> HistoricalRecord {
        HistoricalRecord {
            record_id: id.to_owned(),
            organization_id: "org-1".to_owned(),
            project_id: "project-1".to_owned(),
            scope_item_id: "scope-1".to_owned(),
            location: "E-203".to_owned(),
            change_type: "DRAWING_QUANTITY_INCREASE".to_owned(),
            origin_revision_or_directive: "Rev3/RFI-227".to_owned(),
            time_bucket: "2026-Q1".to_owned(),
            baseline_revision: "Rev2".to_owned(),
            observed_revision: "Rev3".to_owned(),
            baseline_revision_order: 2,
            observed_revision_order: 3,
            baseline_quantity: "42".parse().unwrap(),
            observed_quantity: "48".parse().unwrap(),
            unit: "EA".to_owned(),
            item_mapping_verified: true,
            allowance_remaining: Decimal::ZERO,
            existing_change_order_coverage: false,
            required_baseline_evidence_present: true,
            required_revised_evidence_present: true,
            direction_or_performed_work_verified: true,
            verification_status: VerificationStatus::Verified,
            source_evidence_ids: vec!["e-revised".to_owned(), "e-baseline".to_owned()],
            source_version: "archive-export-v1".to_owned(),
        }
    }

    fn input(records: Vec<HistoricalRecord>) -> HistoricalScanInput {
        HistoricalScanInput {
            schema_version: "historical-rescue/1".to_owned(),
            scan_id: "scan-1".to_owned(),
            organization_id: "org-1".to_owned(),
            project_id: "project-1".to_owned(),
            rule_version: "DRAWING_QUANTITY_INCREASE_V1".to_owned(),
            evaluation_time: "2026-08-29T00:00:00Z".to_owned(),
            records,
        }
    }

    #[test]
    fn verified_delta_is_eligible_for_review() {
        let result = scan_historical(input(vec![record("r-1")])).unwrap();
        assert_eq!(
            result.findings[0].decision,
            HistoricalDecision::EligibleForReview
        );
        assert_eq!(
            result.findings[0].source_evidence_ids,
            vec!["e-baseline", "e-revised"]
        );
    }

    #[test]
    fn direction_gap_is_potential_change_not_authority() {
        let mut value = record("r-1");
        value.direction_or_performed_work_verified = false;
        let result = scan_historical(input(vec![value])).unwrap();
        assert_eq!(
            result.findings[0].decision,
            HistoricalDecision::PotentialChange
        );
        assert_eq!(
            result.findings[0].missing_conditions,
            vec![CONDITION_DIRECTION]
        );
    }

    #[test]
    fn missing_provenance_requires_more_evidence() {
        let mut value = record("r-1");
        value.source_evidence_ids.clear();
        value.source_version.clear();
        let result = scan_historical(input(vec![value])).unwrap();
        assert_eq!(
            result.findings[0].decision,
            HistoricalDecision::MoreEvidenceRequired
        );
        assert!(
            result.findings[0]
                .missing_conditions
                .contains(&"source_provenance".to_owned())
        );
    }

    #[test]
    fn duplicate_key_is_marked_without_dropping_history() {
        let first = record("r-1");
        let second = record("r-2");
        let result = scan_historical(input(vec![second, first])).unwrap();
        assert_eq!(result.findings.len(), 2);
        assert_eq!(result.findings[0].record_id, "r-1");
        assert_eq!(result.findings[1].decision, HistoricalDecision::Duplicate);
    }

    #[test]
    fn replay_hash_is_stable_across_input_order() {
        let left = scan_historical(input(vec![record("r-2"), record("r-1")])).unwrap();
        let right = scan_historical(input(vec![record("r-1"), record("r-2")])).unwrap();
        assert_eq!(left, right);
    }

    #[test]
    fn tenant_boundary_fails_closed() {
        let mut value = record("r-1");
        value.organization_id = "other-org".to_owned();
        assert!(matches!(
            scan_historical(input(vec![value])),
            Err(HistoricalRescueError::OrganizationBoundaryMismatch { .. })
        ));
    }
}
