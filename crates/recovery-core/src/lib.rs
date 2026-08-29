mod attribution;
mod automation;
mod baseline;
mod canonical;
mod engine;
mod historical;
mod pricing;

pub use attribution::{
    AttributionError, AttributionInput, AttributionRecord, AttributionResult, attribute_recovery,
};
pub use automation::{
    ActionCandidate, AutomationError, AutomationMode, AutomationPolicy, AutomationReceipt,
    AutomationStatus, evaluate_action,
};
pub use baseline::{
    BaselineValue, CompileError as BaselineCompileError, CompileInput, CompiledBaseline,
    EvidenceInput as BaselineEvidenceInput, FactInput as BaselineFactInput,
    VerificationStatus as BaselineVerificationStatus, compile as compile_baseline,
};
pub use canonical::{canonical_json, decision_hash};
pub use engine::{EngineError, evaluate_recovery};
pub use historical::{
    HistoricalDecision, HistoricalDeduplicationKey, HistoricalFinding, HistoricalRecord,
    HistoricalRescueError, HistoricalScanInput, HistoricalScanResult, scan_historical,
};
