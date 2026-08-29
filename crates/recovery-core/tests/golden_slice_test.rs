use recovery_core::{EngineError, evaluate_recovery};
use recovery_model::{EvaluationDecision, EvaluationInput, EvaluationRecord};
use rust_decimal::Decimal;

const GOLDEN_INPUT: &str =
    include_str!("../../../fixtures/projects/proj_01/drawing_delta_input.json");
const GOLDEN_EXPECTED: &str =
    include_str!("../../../fixtures/projects/proj_01/drawing_delta_expected.json");

fn input() -> EvaluationInput {
    serde_json::from_str(GOLDEN_INPUT).expect("frozen input fixture must deserialize")
}

#[test]
fn golden_total_and_replay_are_exact() {
    let first = evaluate_recovery(&input()).expect("golden evaluation must succeed");
    let second = evaluate_recovery(&input()).expect("golden replay must succeed");
    let expected: EvaluationRecord =
        serde_json::from_str(GOLDEN_EXPECTED).expect("frozen output fixture must deserialize");

    assert_eq!(first, expected, "full semantic equality diverged");
    assert_eq!(first.decision, second.decision, "semantic replay diverged");
    assert_eq!(
        first.evaluation_hash, second.evaluation_hash,
        "canonical hash replay diverged"
    );

    let EvaluationDecision::Opportunity(opportunity) = &first.decision else {
        panic!("golden fixture must produce an opportunity")
    };
    assert_eq!(opportunity.pricing.raw_subtotal, Decimal::new(456_161, 2));
    assert_eq!(opportunity.pricing.total_markup, Decimal::new(37_662, 2));
    assert_eq!(opportunity.pricing.tax, Decimal::ZERO);
    assert_eq!(opportunity.pricing.total, Decimal::new(493_823, 2));

    println!("{}", serde_json::to_string_pretty(&first).unwrap());
}

#[test]
fn missing_tax_rule_fails_closed() {
    let mut input = input();
    input.pricing_rules.tax_percent = None;
    assert!(matches!(
        evaluate_recovery(&input),
        Err(EngineError::MissingTaxRule)
    ));
}

#[test]
fn currency_mismatch_fails_closed() {
    let mut input = input();
    input.pricing_inputs.material.as_mut().unwrap().currency.0 = "CAD".to_owned();
    assert!(matches!(
        evaluate_recovery(&input),
        Err(EngineError::CurrencyMismatch { .. })
    ));
}

#[test]
fn no_verified_direction_is_not_an_engine_error() {
    let mut evaluation_input = input();
    let recovery_model::FactValue::DrawingQuantityDelta(delta) =
        &mut evaluation_input.verified_facts[0].value;
    delta.direction_or_performed_work_verified = false;

    let record =
        evaluate_recovery(&evaluation_input).expect("valid no-opportunity is a domain decision");
    assert!(matches!(
        record.decision,
        EvaluationDecision::NoOpportunity(_)
    ));
}
