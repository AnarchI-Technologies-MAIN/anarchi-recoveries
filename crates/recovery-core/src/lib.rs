mod attribution;
mod baseline;
mod canonical;
mod engine;
mod pricing;

pub use attribution::{
    AttributionError, AttributionInput, AttributionRecord, AttributionResult, attribute_recovery,
};
pub use baseline::{
    BaselineValue, CompileError as BaselineCompileError, CompileInput, CompiledBaseline,
    EvidenceInput as BaselineEvidenceInput, FactInput as BaselineFactInput,
    VerificationStatus as BaselineVerificationStatus, compile as compile_baseline,
};
pub use canonical::{canonical_json, decision_hash};
pub use engine::{EngineError, evaluate_recovery};
