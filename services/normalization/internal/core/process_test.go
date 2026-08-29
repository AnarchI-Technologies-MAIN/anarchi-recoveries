package core

import (
	"errors"
	"testing"
)

func TestParseSuccessRequiresEvaluationHash(t *testing.T) {
	_, err := ParseResponse([]byte(`{"status":"SUCCESS","record":{"evaluation_hash":"bad"}}`))
	if !errors.Is(err, ErrBoundary) {
		t.Fatalf("expected boundary rejection, got %v", err)
	}
}

func TestParseStructuredError(t *testing.T) {
	response, err := ParseResponse([]byte(`{"status":"ERROR","code":"MISSING_TAX_RULE"}`))
	if err != nil || response.Code != "MISSING_TAX_RULE" {
		t.Fatalf("unexpected response=%+v err=%v", response, err)
	}
}

func TestUnknownStatusFailsClosed(t *testing.T) {
	_, err := ParseResponse([]byte(`{"status":"MAYBE"}`))
	if !errors.Is(err, ErrBoundary) {
		t.Fatalf("expected boundary rejection, got %v", err)
	}
}
