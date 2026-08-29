use serde::Serialize;
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::EngineError;

pub const CANONICALIZATION_VERSION: &str = "ANARCHI-JCS-COMPATIBLE-V1";

pub fn canonical_json<T: Serialize>(value: &T) -> Result<Vec<u8>, EngineError> {
    let value = serde_json::to_value(value).map_err(EngineError::Serialization)?;
    let mut output = String::new();
    write_canonical(&value, &mut output)?;
    Ok(output.into_bytes())
}

pub fn decision_hash<T: Serialize>(value: &T) -> Result<String, EngineError> {
    let canonical = canonical_json(value)?;
    Ok(hex::encode(Sha256::digest(canonical)))
}

fn write_canonical(value: &Value, output: &mut String) -> Result<(), EngineError> {
    match value {
        Value::Null => output.push_str("null"),
        Value::Bool(value) => output.push_str(if *value { "true" } else { "false" }),
        Value::Number(number) => output.push_str(&number.to_string()),
        Value::String(value) => {
            output.push_str(&serde_json::to_string(value).map_err(EngineError::Serialization)?)
        }
        Value::Array(values) => {
            output.push('[');
            for (index, value) in values.iter().enumerate() {
                if index > 0 {
                    output.push(',');
                }
                write_canonical(value, output)?;
            }
            output.push(']');
        }
        Value::Object(values) => {
            output.push('{');
            let mut keys: Vec<&String> = values.keys().collect();
            keys.sort_unstable();
            for (index, key) in keys.into_iter().enumerate() {
                if index > 0 {
                    output.push(',');
                }
                output.push_str(&serde_json::to_string(key).map_err(EngineError::Serialization)?);
                output.push(':');
                write_canonical(&values[key], output)?;
            }
            output.push('}');
        }
    }
    Ok(())
}
