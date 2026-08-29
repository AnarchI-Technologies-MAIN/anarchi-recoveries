package extraction

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

type extractorFake struct{ candidates []Candidate }

func (f extractorFake) Extract(context.Context, string) ([]Candidate, error) {
	return f.candidates, nil
}

type repoFake struct{ calls int }

func (f *repoFake) PersistCandidateBatch(context.Context, []Candidate) error { f.calls++; return nil }

func candidate() Candidate {
	return Candidate{
		FactID: "00000000-0000-4000-8000-000000001304", OrganizationID: "00000000-0000-4000-8000-000000001301",
		ProjectID: "00000000-0000-4000-8000-000000001302", FactType: "DRAWING_QUANTITY", Subject: "panel P1",
		Value: json.RawMessage(`{"quantity":"12.0000000000"}`), SourceEvidenceID: "00000000-0000-4000-8000-000000001303",
		SourceLocation: "page=2,bbox=10,20,30,40", ExtractionMethod: "MODEL",
		ModelOrParserVersion: "proof-model@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		CandidateConfidence:  "0.87500", EventID: "00000000-0000-4000-8000-000000001305",
		CorrelationID: "00000000-0000-4000-8000-000000001306", IdempotencyKey: "candidate-1",
	}
}

func TestValidBatchPersistsOnce(t *testing.T) {
	repo := &repoFake{}
	service, _ := New(extractorFake{candidates: []Candidate{candidate()}}, repo)
	got, err := service.ExtractCandidates(context.Background(), "s3://proof/evidence")
	if err != nil || len(got) != 1 || repo.calls != 1 {
		t.Fatalf("unexpected result len=%d calls=%d err=%v", len(got), repo.calls, err)
	}
}

func TestInvalidCandidateRejectsWholeBatch(t *testing.T) {
	bad := candidate()
	bad.ModelOrParserVersion = "floating-model-name"
	repo := &repoFake{}
	service, _ := New(extractorFake{candidates: []Candidate{candidate(), bad}}, repo)
	_, err := service.ExtractCandidates(context.Background(), "s3://proof/evidence")
	if !errors.Is(err, ErrCandidate) || repo.calls != 0 {
		t.Fatalf("expected fail-closed batch, calls=%d err=%v", repo.calls, err)
	}
}

func TestCandidateWireTypeHasNoVerificationAuthority(t *testing.T) {
	wire, err := json.Marshal(candidate())
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(wire), "verification") || strings.Contains(string(wire), "verified") {
		t.Fatalf("candidate wire type leaked verification authority: %s", wire)
	}
}
