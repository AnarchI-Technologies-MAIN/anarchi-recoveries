package extraction

import (
	"context"
	"encoding/json"
	"errors"
	"regexp"
	"strings"
)

var (
	ErrCandidate = errors.New("invalid candidate fact")
	uuidPattern  = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)
	modelPattern = regexp.MustCompile(`^[^@]+@sha256:[0-9a-f]{64}$`)
)

type Candidate struct {
	FactID               string          `json:"fact_id"`
	OrganizationID       string          `json:"organization_id"`
	ProjectID            string          `json:"project_id"`
	FactType             string          `json:"fact_type"`
	Subject              string          `json:"subject"`
	Value                json.RawMessage `json:"value"`
	Unit                 *string         `json:"unit,omitempty"`
	Currency             *string         `json:"currency,omitempty"`
	SourceEvidenceID     string          `json:"source_evidence_id"`
	SourceLocation       string          `json:"source_location"`
	ExtractionMethod     string          `json:"extraction_method"`
	ModelOrParserVersion string          `json:"model_or_parser_version"`
	CandidateConfidence  string          `json:"candidate_confidence"`
	EventID              string          `json:"-"`
	OccurredAt           string          `json:"-"`
	CausationID          string          `json:"-"`
	CorrelationID        string          `json:"-"`
	IdempotencyKey       string          `json:"-"`
}

type Extractor interface {
	Extract(context.Context, string) ([]Candidate, error)
}

type Repository interface {
	PersistCandidateBatch(context.Context, []Candidate) error
}

type Service struct {
	extractor Extractor
	repo      Repository
}

func New(extractor Extractor, repo Repository) (*Service, error) {
	if extractor == nil || repo == nil {
		return nil, errors.New("extractor and repository are required")
	}
	return &Service{extractor: extractor, repo: repo}, nil
}

func (s *Service) ExtractCandidates(ctx context.Context, evidenceURI string) ([]Candidate, error) {
	if !strings.HasPrefix(evidenceURI, "s3://") {
		return nil, ErrCandidate
	}
	candidates, err := s.extractor.Extract(ctx, evidenceURI)
	if err != nil {
		return nil, err
	}
	for _, candidate := range candidates {
		if err := Validate(candidate); err != nil {
			return nil, err
		}
	}
	if err := s.repo.PersistCandidateBatch(ctx, candidates); err != nil {
		return nil, err
	}
	return candidates, nil
}

func Validate(v Candidate) error {
	if !uuidPattern.MatchString(v.FactID) || !uuidPattern.MatchString(v.OrganizationID) ||
		!uuidPattern.MatchString(v.ProjectID) || !uuidPattern.MatchString(v.SourceEvidenceID) ||
		!uuidPattern.MatchString(v.EventID) || !uuidPattern.MatchString(v.CorrelationID) {
		return ErrCandidate
	}
	if v.CausationID != "" && !uuidPattern.MatchString(v.CausationID) {
		return ErrCandidate
	}
	if strings.TrimSpace(v.FactType) == "" || strings.TrimSpace(v.Subject) == "" ||
		strings.TrimSpace(v.SourceLocation) == "" || strings.TrimSpace(v.IdempotencyKey) == "" {
		return ErrCandidate
	}
	var object map[string]any
	if err := json.Unmarshal(v.Value, &object); err != nil || object == nil {
		return ErrCandidate
	}
	if v.ExtractionMethod == "MODEL" && !modelPattern.MatchString(v.ModelOrParserVersion) {
		return ErrCandidate
	}
	if v.ExtractionMethod != "MODEL" && v.ExtractionMethod != "PARSER" && v.ExtractionMethod != "OCR" {
		return ErrCandidate
	}
	if !regexp.MustCompile(`^(0(\.\d{1,5})?|1(\.0{1,5})?)$`).MatchString(v.CandidateConfidence) {
		return ErrCandidate
	}
	return nil
}
