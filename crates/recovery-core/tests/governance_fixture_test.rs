use recovery_core::{GovernanceRequest, GovernanceResult, authorize_external_notice};
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
