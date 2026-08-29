use recovery_model::{
    CurrencyCode, EvidenceId, PricingCalculation, PricingInputs, PricingLine, PricingLineClass,
    PricingRules, RoundingMode,
};
use rust_decimal::{Decimal, RoundingStrategy};

use crate::EngineError;

pub(crate) fn calculate_price(
    inputs: &PricingInputs,
    rules: &PricingRules,
) -> Result<PricingCalculation, EngineError> {
    validate_rules(rules)?;
    let mut lines = Vec::new();

    for labor in &inputs.labor {
        require_currency(&labor.currency, &rules.currency)?;
        let amount = round(labor.hours * labor.hourly_rate, rules);
        lines.push(PricingLine {
            class: PricingLineClass::Labor,
            description: labor.classification.clone(),
            amount,
            currency: rules.currency.clone(),
            evidence_ids: vec![labor.evidence.evidence_id.clone()],
            rule_version: rules.version.clone(),
        });
    }

    let material = inputs
        .material
        .as_ref()
        .ok_or(EngineError::MissingMaterialCost)?;
    require_currency(&material.currency, &rules.currency)?;
    let material_amount = round(material.amount, rules);
    lines.push(cost_line(
        PricingLineClass::Material,
        material.description.clone(),
        material_amount,
        material.evidence.evidence_id.clone(),
        rules,
    ));

    let equipment = inputs
        .equipment
        .as_ref()
        .ok_or(EngineError::MissingEquipmentCost)?;
    require_currency(&equipment.currency, &rules.currency)?;
    let equipment_amount = round(equipment.amount, rules);
    lines.push(cost_line(
        PricingLineClass::Equipment,
        equipment.description.clone(),
        equipment_amount,
        equipment.evidence.evidence_id.clone(),
        rules,
    ));

    let raw_subtotal = lines.iter().map(|line| line.amount).sum();
    let material_markup = round(
        material_amount
            * rules
                .material_markup_percent
                .ok_or(EngineError::MissingMaterialMarkupRule)?
            / Decimal::ONE_HUNDRED,
        rules,
    );
    lines.push(cost_line(
        PricingLineClass::MaterialMarkup,
        "material markup".to_owned(),
        material_markup,
        material.evidence.evidence_id.clone(),
        rules,
    ));

    let equipment_markup = round(
        equipment_amount
            * rules
                .equipment_markup_percent
                .ok_or(EngineError::MissingEquipmentMarkupRule)?
            / Decimal::ONE_HUNDRED,
        rules,
    );
    lines.push(cost_line(
        PricingLineClass::EquipmentMarkup,
        "equipment markup".to_owned(),
        equipment_markup,
        equipment.evidence.evidence_id.clone(),
        rules,
    ));

    let total_markup = material_markup + equipment_markup;
    let tax = round(
        (raw_subtotal + total_markup) * rules.tax_percent.ok_or(EngineError::MissingTaxRule)?
            / Decimal::ONE_HUNDRED,
        rules,
    );
    lines.push(PricingLine {
        class: PricingLineClass::Tax,
        description: "tax".to_owned(),
        amount: tax,
        currency: rules.currency.clone(),
        evidence_ids: Vec::new(),
        rule_version: rules.version.clone(),
    });

    Ok(PricingCalculation {
        currency: rules.currency.clone(),
        lines,
        raw_subtotal,
        total_markup,
        tax,
        total: raw_subtotal + total_markup + tax,
        pricing_rule_version: rules.version.clone(),
    })
}

fn validate_rules(rules: &PricingRules) -> Result<(), EngineError> {
    if rules.version.trim().is_empty() {
        return Err(EngineError::MissingPricingRuleVersion);
    }
    if rules.currency.0.len() != 3 || !rules.currency.0.chars().all(|c| c.is_ascii_uppercase()) {
        return Err(EngineError::InvalidCurrency(rules.currency.0.clone()));
    }
    if rules.money_scale != 2 {
        return Err(EngineError::UnsupportedMoneyScale(rules.money_scale));
    }
    if rules.rounding_mode != RoundingMode::MidpointAwayFromZero {
        return Err(EngineError::UnsupportedRoundingRule);
    }
    Ok(())
}

fn require_currency(actual: &CurrencyCode, expected: &CurrencyCode) -> Result<(), EngineError> {
    if actual != expected {
        return Err(EngineError::CurrencyMismatch {
            expected: expected.0.clone(),
            actual: actual.0.clone(),
        });
    }
    Ok(())
}

fn round(value: Decimal, rules: &PricingRules) -> Decimal {
    let mut rounded =
        value.round_dp_with_strategy(rules.money_scale, RoundingStrategy::MidpointAwayFromZero);
    rounded.rescale(rules.money_scale);
    rounded
}

fn cost_line(
    class: PricingLineClass,
    description: String,
    amount: Decimal,
    evidence_id: EvidenceId,
    rules: &PricingRules,
) -> PricingLine {
    PricingLine {
        class,
        description,
        amount,
        currency: rules.currency.clone(),
        evidence_ids: vec![evidence_id],
        rule_version: rules.version.clone(),
    }
}
