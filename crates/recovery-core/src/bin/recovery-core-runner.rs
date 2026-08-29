use recovery_core::evaluate_recovery;
use recovery_model::{EvaluationInput, EvaluationRecord};
use serde::Serialize;
use std::io::{self, Read};

#[derive(Serialize)]
#[serde(tag = "status", rename_all = "SCREAMING_SNAKE_CASE")]
enum Response {
    Success { record: EvaluationRecord },
    Error { code: &'static str },
}

fn main() {
    let mut input = Vec::new();
    if io::stdin().read_to_end(&mut input).is_err() {
        write(Response::Error {
            code: "INPUT_IO_ERROR",
        });
        return;
    }
    let request: EvaluationInput = match serde_json::from_slice(&input) {
        Ok(value) => value,
        Err(_) => {
            write(Response::Error {
                code: "INVALID_INPUT",
            });
            return;
        }
    };
    match evaluate_recovery(&request) {
        Ok(record) => write(Response::Success { record }),
        Err(error) => write(Response::Error { code: error.code() }),
    }
}

fn write(response: Response) {
    serde_json::to_writer(io::stdout().lock(), &response)
        .expect("serializing the fixed response envelope cannot fail");
}
