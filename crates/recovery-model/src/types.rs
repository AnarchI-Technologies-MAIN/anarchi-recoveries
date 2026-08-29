use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};

macro_rules! string_id {
    ($name:ident) => {
        #[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
        #[serde(transparent)]
        pub struct $name(pub String);
    };
}

string_id!(OrganizationId);
string_id!(ProjectId);
string_id!(EvidenceId);
string_id!(FactId);
string_id!(BaselineId);
string_id!(ScopeItemId);

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct CurrencyCode(pub String);

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VersionRef {
    pub identifier: String,
    pub version: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EvidenceReference {
    pub evidence_id: EvidenceId,
    pub sha256: String,
    pub source_location: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum VerificationStatus {
    Candidate,
    Verified,
    Rejected,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VerifiedDrawingQuantityDelta {
    pub scope_item_id: ScopeItemId,
    pub baseline_revision: String,
    pub observed_revision: String,
    #[serde(with = "rust_decimal::serde::str")]
    pub baseline_quantity: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub observed_quantity: Decimal,
    pub unit: String,
    pub item_mapping_verified: bool,
    pub direction_or_performed_work_verified: bool,
    pub existing_change_order_coverage: bool,
    #[serde(with = "rust_decimal::serde::str")]
    pub allowance_remaining: Decimal,
    pub baseline_evidence: EvidenceReference,
    pub revised_evidence: EvidenceReference,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "fact_type",
    content = "value",
    rename_all = "SCREAMING_SNAKE_CASE"
)]
pub enum FactValue {
    DrawingQuantityDelta(VerifiedDrawingQuantityDelta),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VerifiedFact {
    pub fact_id: FactId,
    pub organization_id: OrganizationId,
    pub project_id: ProjectId,
    pub verification_status: VerificationStatus,
    pub verified_by: String,
    pub verified_at: String,
    pub parser_or_model: VersionRef,
    pub evidence: Vec<EvidenceReference>,
    pub value: FactValue,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContractBaseline {
    pub baseline_id: BaselineId,
    pub organization_id: OrganizationId,
    pub project_id: ProjectId,
    pub version: u32,
    pub status: BaselineStatus,
    pub evidence: Vec<EvidenceReference>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum BaselineStatus {
    Draft,
    Active,
    Superseded,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LaborInput {
    pub classification: String,
    #[serde(with = "rust_decimal::serde::str")]
    pub hours: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub hourly_rate: Decimal,
    pub currency: CurrencyCode,
    pub evidence: EvidenceReference,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CostInput {
    pub description: String,
    #[serde(with = "rust_decimal::serde::str")]
    pub amount: Decimal,
    pub currency: CurrencyCode,
    pub evidence: EvidenceReference,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PricingInputs {
    pub labor: Vec<LaborInput>,
    pub material: Option<CostInput>,
    pub equipment: Option<CostInput>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum RoundingMode {
    MidpointAwayFromZero,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PricingRules {
    pub version: String,
    pub currency: CurrencyCode,
    pub money_scale: u32,
    pub rounding_mode: RoundingMode,
    #[serde(with = "rust_decimal::serde::str_option")]
    pub material_markup_percent: Option<Decimal>,
    #[serde(with = "rust_decimal::serde::str_option")]
    pub equipment_markup_percent: Option<Decimal>,
    #[serde(with = "rust_decimal::serde::str_option")]
    pub tax_percent: Option<Decimal>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EvaluationInput {
    pub schema_version: String,
    pub organization_id: OrganizationId,
    pub project_id: ProjectId,
    pub evaluation_time: String,
    pub baseline: ContractBaseline,
    pub verified_facts: Vec<VerifiedFact>,
    pub domain_rules: VersionRef,
    pub notice_rules: VersionRef,
    pub pricing_rules: PricingRules,
    pub pricing_inputs: PricingInputs,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PricingLine {
    pub class: PricingLineClass,
    pub description: String,
    #[serde(with = "rust_decimal::serde::str")]
    pub amount: Decimal,
    pub currency: CurrencyCode,
    pub evidence_ids: Vec<EvidenceId>,
    pub rule_version: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum PricingLineClass {
    Labor,
    Material,
    Equipment,
    MaterialMarkup,
    EquipmentMarkup,
    Tax,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PricingCalculation {
    pub currency: CurrencyCode,
    pub lines: Vec<PricingLine>,
    #[serde(with = "rust_decimal::serde::str")]
    pub raw_subtotal: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub total_markup: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub tax: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub total: Decimal,
    pub pricing_rule_version: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OpportunityDecision {
    pub organization_id: OrganizationId,
    pub project_id: ProjectId,
    pub baseline_id: BaselineId,
    pub evaluation_time: String,
    pub domain_rule_version: String,
    pub notice_rule_version: String,
    pub passed_conditions: Vec<String>,
    pub failed_conditions: Vec<String>,
    pub missing_conditions: Vec<String>,
    pub facts_used: Vec<FactId>,
    pub pricing: PricingCalculation,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "decision",
    content = "result",
    rename_all = "SCREAMING_SNAKE_CASE"
)]
pub enum EvaluationDecision {
    Opportunity(Box<OpportunityDecision>),
    NoOpportunity(NoOpportunityReason),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum NoOpportunityReason {
    NoVerifiedDrawingDelta,
    ItemMappingUnverified,
    NonPositiveQuantityDelta,
    AllowanceRemaining,
    ExistingChangeOrderCoverage,
    DirectionOrPerformedWorkUnverified,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EvaluationRecord {
    pub canonicalization: String,
    pub decision: EvaluationDecision,
    pub evaluation_hash: String,
}
