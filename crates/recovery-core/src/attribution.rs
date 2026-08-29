use recovery_model::{CurrencyCode, RoundingMode};
use rust_decimal::{Decimal, RoundingStrategy};
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::canonical::CANONICALIZATION_VERSION;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttributionInput {
    pub attribution_rule_version: String,
    pub currency: CurrencyCode,
    #[serde(with = "rust_decimal::serde::str")]
    pub supported_value: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub prior_recognized_supported_value: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub attributable_cash_received: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub success_fee_rate_percent: Decimal,
    pub money_scale: u32,
    pub rounding_mode: RoundingMode,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttributionResult {
    pub attribution_rule_version: String,
    pub currency: CurrencyCode,
    #[serde(with = "rust_decimal::serde::str")]
    pub supported_value: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub prior_recognized_supported_value: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub attributable_supported_uplift: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub attributable_cash_received: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub success_fee_rate_percent: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub success_fee_base: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub success_fee: Decimal,
    pub money_scale: u32,
    pub rounding_mode: RoundingMode,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttributionRecord {
    pub canonicalization: String,
    pub result: AttributionResult,
    pub attribution_hash: String,
}

#[derive(Debug, Error)]
pub enum AttributionError {
    #[error("attribution rule version is required")]
    MissingRuleVersion,
    #[error("invalid ISO currency: {0}")]
    InvalidCurrency(String),
    #[error("attribution values cannot be negative")]
    NegativeValue,
    #[error("success fee rate must be between zero and one hundred percent")]
    InvalidFeeRate,
    #[error("unsupported money scale: {0}")]
    UnsupportedMoneyScale(u32),
    #[error("unsupported rounding rule")]
    UnsupportedRoundingRule,
    #[error("attribution arithmetic overflow")]
    ArithmeticOverflow,
    #[error("serialization failed: {0}")]
    Serialization(serde_json::Error),
}

pub fn attribute_recovery(input: &AttributionInput) -> Result<AttributionRecord, AttributionError> {
    validate(input)?;

    let uplift =
        (input.supported_value - input.prior_recognized_supported_value).max(Decimal::ZERO);
    let cash_base = input.attributable_cash_received.min(uplift);
    let fee_base = round(cash_base, input.money_scale);
    let fee = round(
        fee_base
            .checked_mul(input.success_fee_rate_percent)
            .ok_or(AttributionError::ArithmeticOverflow)?
            .checked_div(Decimal::ONE_HUNDRED)
            .ok_or(AttributionError::ArithmeticOverflow)?,
        input.money_scale,
    );
    let result = AttributionResult {
        attribution_rule_version: input.attribution_rule_version.clone(),
        currency: input.currency.clone(),
        supported_value: input.supported_value,
        prior_recognized_supported_value: input.prior_recognized_supported_value,
        attributable_supported_uplift: round(uplift, input.money_scale),
        attributable_cash_received: input.attributable_cash_received,
        success_fee_rate_percent: input.success_fee_rate_percent,
        success_fee_base: fee_base,
        success_fee: fee,
        money_scale: input.money_scale,
        rounding_mode: input.rounding_mode,
    };
    let attribution_hash = crate::decision_hash(&result).map_err(|error| match error {
        crate::EngineError::Serialization(error) => AttributionError::Serialization(error),
        _ => AttributionError::Serialization(serde_json::Error::io(std::io::Error::other(
            "unexpected canonicalization error",
        ))),
    })?;
    Ok(AttributionRecord {
        canonicalization: CANONICALIZATION_VERSION.to_owned(),
        result,
        attribution_hash,
    })
}

fn validate(input: &AttributionInput) -> Result<(), AttributionError> {
    if input.attribution_rule_version.trim().is_empty() {
        return Err(AttributionError::MissingRuleVersion);
    }
    if input.currency.0.len() != 3 || !input.currency.0.chars().all(|c| c.is_ascii_uppercase()) {
        return Err(AttributionError::InvalidCurrency(input.currency.0.clone()));
    }
    if input.supported_value < Decimal::ZERO
        || input.prior_recognized_supported_value < Decimal::ZERO
        || input.attributable_cash_received < Decimal::ZERO
    {
        return Err(AttributionError::NegativeValue);
    }
    if input.success_fee_rate_percent < Decimal::ZERO
        || input.success_fee_rate_percent > Decimal::ONE_HUNDRED
    {
        return Err(AttributionError::InvalidFeeRate);
    }
    if input.money_scale != 2 {
        return Err(AttributionError::UnsupportedMoneyScale(input.money_scale));
    }
    if input.rounding_mode != RoundingMode::MidpointAwayFromZero {
        return Err(AttributionError::UnsupportedRoundingRule);
    }
    Ok(())
}

fn round(value: Decimal, scale: u32) -> Decimal {
    let mut rounded = value.round_dp_with_strategy(scale, RoundingStrategy::MidpointAwayFromZero);
    rounded.rescale(scale);
    rounded
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input(supported: &str, prior: &str, cash: &str, rate: &str) -> AttributionInput {
        AttributionInput {
            attribution_rule_version: "SUCCESS_FEE_V1".to_owned(),
            currency: CurrencyCode("USD".to_owned()),
            supported_value: supported.parse().unwrap(),
            prior_recognized_supported_value: prior.parse().unwrap(),
            attributable_cash_received: cash.parse().unwrap(),
            success_fee_rate_percent: rate.parse().unwrap(),
            money_scale: 2,
            rounding_mode: RoundingMode::MidpointAwayFromZero,
        }
    }

    #[test]
    fn partial_cash_is_fee_limited() {
        let record = attribute_recovery(&input("10000.00", "0.00", "4000.00", "15.00")).unwrap();
        assert_eq!(
            record.result.attributable_supported_uplift,
            Decimal::new(1000000, 2)
        );
        assert_eq!(record.result.success_fee_base, Decimal::new(400000, 2));
        assert_eq!(record.result.success_fee, Decimal::new(60000, 2));
    }

    #[test]
    fn prior_recognition_creates_only_incremental_uplift() {
        let record = attribute_recovery(&input("12481.23", "8000.00", "4481.23", "15.00")).unwrap();
        assert_eq!(
            record.result.attributable_supported_uplift,
            Decimal::new(448123, 2)
        );
        assert_eq!(record.result.success_fee, Decimal::new(67218, 2));
    }

    #[test]
    fn verification_only_has_zero_fee() {
        let record = attribute_recovery(&input("8000.00", "8000.00", "4000.00", "15.00")).unwrap();
        assert_eq!(record.result.attributable_supported_uplift, Decimal::ZERO);
        assert_eq!(record.result.success_fee, Decimal::ZERO);
    }

    #[test]
    fn cash_above_uplift_is_capped() {
        let record = attribute_recovery(&input("100.00", "0.00", "125.00", "20.00")).unwrap();
        assert_eq!(record.result.success_fee_base, Decimal::new(10000, 2));
        assert_eq!(record.result.success_fee, Decimal::new(2000, 2));
    }

    #[test]
    fn replay_hash_is_stable() {
        let first = attribute_recovery(&input("12481.23", "8000.00", "4481.23", "15.00")).unwrap();
        let second = attribute_recovery(&input("12481.23", "8000.00", "4481.23", "15.00")).unwrap();
        assert_eq!(first, second);
        assert!(crate::canonical::canonical_json(&first.result).is_ok());
    }

    #[test]
    fn invalid_values_fail_closed() {
        assert!(matches!(
            attribute_recovery(&input("-1.00", "0.00", "0.00", "15.00")),
            Err(AttributionError::NegativeValue)
        ));
        assert!(matches!(
            attribute_recovery(&input("1.00", "0.00", "0.00", "101.00")),
            Err(AttributionError::InvalidFeeRate)
        ));
    }
}
