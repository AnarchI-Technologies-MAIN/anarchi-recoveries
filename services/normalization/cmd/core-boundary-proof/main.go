package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"anarchi.tech/recoveries/normalization/internal/core"
)

func main() {
	if len(os.Args) != 4 {
		panic("usage: core-boundary-proof RUNNER INPUT EXPECTED")
	}
	input, err := os.ReadFile(os.Args[2])
	must(err)
	expected, err := os.ReadFile(os.Args[3])
	must(err)
	runner, err := core.NewProcessRunner(os.Args[1])
	must(err)
	response, err := runner.Evaluate(context.Background(), input)
	must(err)
	if response.Status != "SUCCESS" {
		panic("recovery core returned " + response.Code)
	}
	var actualValue any
	var expectedValue any
	must(json.Unmarshal(response.Record, &actualValue))
	must(json.Unmarshal(expected, &expectedValue))
	if !equalJSON(actualValue, expectedValue) {
		panic("recovery core result diverged from frozen expected output")
	}
	var record struct {
		EvaluationHash string `json:"evaluation_hash"`
	}
	must(json.Unmarshal(response.Record, &record))
	fmt.Printf("result=PASS_GO_WORKER_RUST_CORE_BOUNDARY\nevaluation_hash=%s\n", record.EvaluationHash)
}

func equalJSON(left, right any) bool {
	l, _ := json.Marshal(left)
	r, _ := json.Marshal(right)
	return string(l) == string(r)
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
