use recovery_core::{
    DecisionReceiptError, GovernanceRequest, GovernanceResult, authorize_external_notice,
    issue_decision_receipt, verify_decision_receipt,
};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Fixture {
    request: GovernanceRequest,
    expected: Expected,
}

#[derive(Debug, Deserialize)]
struct Expected {
    result: GovernanceResult,
    reason_code: String,
}

#[derive(Debug, Deserialize)]
struct MutationFixture {
    approved_payload_hash: String,
    mutated_payload_hash: String,
    expected: Expected,
}

#[test]
fn no_approval_fixture_is_denied() {
    let fixture: Fixture = serde_json::from_str(include_str!(
        "../../../fixtures/governance/notice-denied-without-authority.json"
    ))
    .unwrap();
    let decision = authorize_external_notice(&fixture.request).unwrap();
    assert_eq!(decision.result, fixture.expected.result);
    assert_eq!(decision.reason_code, fixture.expected.reason_code);
}

#[test]
fn approved_fixture_is_allowed() {
    let fixture: Fixture = serde_json::from_str(include_str!(
        "../../../fixtures/governance/notice-allowed-with-authority.json"
    ))
    .unwrap();
    let decision = authorize_external_notice(&fixture.request).unwrap();
    assert_eq!(decision.result, fixture.expected.result);
    assert_eq!(decision.reason_code, fixture.expected.reason_code);
}

#[test]
fn payload_mutation_fixture_is_denied() {
    let fixture: MutationFixture = serde_json::from_str(include_str!(
        "../../../fixtures/governance/notice-payload-mutation-denied.json"
    ))
    .unwrap();
    let mut request = GovernanceRequest {
        subject: "user-1".to_owned(),
        organization_id: "org-1".to_owned(),
        operation: "submit_external_notice".to_owned(),
        resource: "opportunity-1".to_owned(),
        purpose: "recovery_notice".to_owned(),
        policy_version: "RECOVERIES_AUTH_V1".to_owned(),
        payload_hash: fixture.approved_payload_hash.clone(),
        human_approval_id: Some("approval-1".to_owned()),
    };
    let decision = authorize_external_notice(&request).unwrap();
    let receipt = issue_decision_receipt(
        &request,
        &decision,
        "decision-1",
        "recovery_notice",
        "2026-08-30T00:00:00Z",
    )
    .unwrap();
    request.payload_hash = fixture.mutated_payload_hash;
    let error = verify_decision_receipt(&receipt, &request.payload_hash).unwrap_err();
    assert_eq!(error.code(), fixture.expected.reason_code);
    assert!(matches!(error, DecisionReceiptError::PayloadMismatch));
}
