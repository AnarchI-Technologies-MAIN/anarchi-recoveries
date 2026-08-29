//! Deterministic compiler for reviewed, evidence-backed contract baselines.

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum CompileError {
    #[error("baseline requires at least one evidence item and one fact")]
    Empty,
    #[error("all baseline facts must be verified")]
    UnverifiedFact,
    #[error("fact source evidence is missing from baseline evidence")]
    MissingEvidence,
    #[error("duplicate stable identity")]
    DuplicateIdentity,
    #[error("canonical serialization failed")]
    Serialization,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum VerificationStatus {
    Candidate,
    Verified,
    Rejected,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum BaselineValue {
    Quantity { quantity: Decimal, unit: String },
    Money { amount: Decimal, currency: String },
    Text { text: String },
    Boolean { value: bool },
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct EvidenceInput {
    pub evidence_id: String,
    pub source_version: String,
    pub sha256: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct FactInput {
    pub fact_id: String,
    pub fact_type: String,
    pub subject: String,
    pub value: BaselineValue,
    pub source_evidence_id: String,
    pub source_location: String,
    pub model_or_parser_version: String,
    pub verification_status: VerificationStatus,
    pub verified_by: String,
    pub verified_at: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct CompileInput {
    pub schema_version: String,
    pub compiler_version: String,
    pub organization_id: String,
    pub project_id: String,
    pub baseline_id: String,
    pub baseline_version: u32,
    pub evidence: Vec<EvidenceInput>,
    pub facts: Vec<FactInput>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CompiledBaseline {
    pub canonical_json: Vec<u8>,
    pub canonical_sha256: String,
}

pub fn compile(mut input: CompileInput) -> Result<CompiledBaseline, CompileError> {
    if input.evidence.is_empty() || input.facts.is_empty() {
        return Err(CompileError::Empty);
    }
    if input
        .facts
        .iter()
        .any(|fact| fact.verification_status != VerificationStatus::Verified)
    {
        return Err(CompileError::UnverifiedFact);
    }

    input
        .evidence
        .sort_by(|a, b| a.evidence_id.cmp(&b.evidence_id));
    input.facts.sort_by(|a, b| a.fact_id.cmp(&b.fact_id));

    let evidence_ids: BTreeSet<&str> = input
        .evidence
        .iter()
        .map(|item| item.evidence_id.as_str())
        .collect();
    if evidence_ids.len() != input.evidence.len() {
        return Err(CompileError::DuplicateIdentity);
    }
    let fact_ids: BTreeSet<&str> = input
        .facts
        .iter()
        .map(|item| item.fact_id.as_str())
        .collect();
    if fact_ids.len() != input.facts.len() {
        return Err(CompileError::DuplicateIdentity);
    }
    if input
        .facts
        .iter()
        .any(|fact| !evidence_ids.contains(fact.source_evidence_id.as_str()))
    {
        return Err(CompileError::MissingEvidence);
    }

    let canonical_json = serde_json::to_vec(&input).map_err(|_| CompileError::Serialization)?;
    let canonical_sha256 = hex::encode(Sha256::digest(&canonical_json));
    Ok(CompiledBaseline {
        canonical_json,
        canonical_sha256,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input() -> CompileInput {
        CompileInput {
            schema_version: "1.0".into(),
            compiler_version: "baseline-compiler/0.1.0".into(),
            organization_id: "00000000-0000-4000-8000-000000001401".into(),
            project_id: "00000000-0000-4000-8000-000000001404".into(),
            baseline_id: "00000000-0000-4000-8000-000000001407".into(),
            baseline_version: 1,
            evidence: vec![
                EvidenceInput { evidence_id: "b".into(), source_version: "2".into(), sha256: "bb".repeat(32) },
                EvidenceInput { evidence_id: "a".into(), source_version: "1".into(), sha256: "aa".repeat(32) },
            ],
            facts: vec![
                FactInput {
                    fact_id: "2".into(), fact_type: "NOTICE_TERM".into(), subject: "notice".into(),
                    value: BaselineValue::Text { text: "7 days".into() }, source_evidence_id: "b".into(),
                    source_location: "page=9".into(), model_or_parser_version: "parser/1".into(),
                    verification_status: VerificationStatus::Verified, verified_by: "reviewer".into(),
                    verified_at: "2026-08-29T00:00:00Z".into(),
                },
                FactInput {
                    fact_id: "1".into(), fact_type: "DRAWING_QUANTITY".into(), subject: "panel P1".into(),
                    value: BaselineValue::Quantity { quantity: Decimal::new(120, 1), unit: "EA".into() },
                    source_evidence_id: "a".into(), source_location: "page=2".into(),
                    model_or_parser_version: "model@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into(),
                    verification_status: VerificationStatus::Verified, verified_by: "reviewer".into(),
                    verified_at: "2026-08-29T00:00:00Z".into(),
                },
            ],
        }
    }

    #[test]
    fn input_order_does_not_change_hash() {
        let left = compile(input()).unwrap();
        assert_eq!(
            left.canonical_sha256,
            "86cad8649df353ee16f6598edd90d051a7f27d9f9d36d6c91c1d29f2678a5843"
        );
        let mut reversed = input();
        reversed.evidence.reverse();
        reversed.facts.reverse();
        let right = compile(reversed).unwrap();
        assert_eq!(left, right);
    }

    #[test]
    fn candidate_fact_fails_closed() {
        let mut value = input();
        value.facts[0].verification_status = VerificationStatus::Candidate;
        assert_eq!(compile(value), Err(CompileError::UnverifiedFact));
    }

    #[test]
    fn missing_source_evidence_fails_closed() {
        let mut value = input();
        value.facts[0].source_evidence_id = "missing".into();
        assert_eq!(compile(value), Err(CompileError::MissingEvidence));
    }
}
