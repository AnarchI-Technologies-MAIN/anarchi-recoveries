package ingest

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"mime"
	"strings"
	"time"

	"anarchi.tech/recoveries/ingestion/internal/evidence"
	"github.com/google/uuid"
)

var (
	ErrRemoteIntegrity = errors.New("remote evidence integrity mismatch")
	ErrEmptyBucket     = errors.New("evidence bucket is required")
	ErrRequest         = errors.New("invalid ingestion request")
)

type Request struct {
	Identity         evidence.Identity
	Bucket           string
	SourceSystem     string
	ExternalID       string
	SourceVersion    string
	SourceObservedAt string
	MIMEType         string
	SizeBytes        int64
	CorrelationID    string
	CausationID      string
	IdempotencyKey   string
	EventID          string
	OccurredAt       string
	Body             []byte
}

type ObjectMetadata struct {
	SHA256   string
	Filename string
	Size     int64
}

type ObjectStore interface {
	PutIfAbsent(context.Context, string, string, []byte, ObjectMetadata) error
	Head(context.Context, string, string) (ObjectMetadata, error)
}

type EvidenceRecord struct {
	Request
	ObjectURI string
}

type Repository interface {
	PersistEvidenceAndOutbox(context.Context, EvidenceRecord) error
}

type Service struct {
	objects ObjectStore
	repo    Repository
}

func New(objects ObjectStore, repo Repository) (*Service, error) {
	if objects == nil || repo == nil {
		return nil, errors.New("object store and repository are required")
	}
	return &Service{objects: objects, repo: repo}, nil
}

func (s *Service) Ingest(ctx context.Context, req Request) (EvidenceRecord, error) {
	if err := validateRequest(req); err != nil {
		return EvidenceRecord{}, err
	}
	key, err := evidence.ObjectKey(req.Identity)
	if err != nil {
		return EvidenceRecord{}, err
	}
	if err := evidence.Verify(bytes.NewReader(req.Body), req.Identity.SHA256, req.SizeBytes); err != nil {
		return EvidenceRecord{}, err
	}
	metadata := ObjectMetadata{SHA256: req.Identity.SHA256, Filename: req.Identity.Filename, Size: req.SizeBytes}
	if err := s.objects.PutIfAbsent(ctx, req.Bucket, key, req.Body, metadata); err != nil {
		return EvidenceRecord{}, fmt.Errorf("put evidence object: %w", err)
	}
	remote, err := s.objects.Head(ctx, req.Bucket, key)
	if err != nil {
		return EvidenceRecord{}, fmt.Errorf("head evidence object: %w", err)
	}
	if remote != metadata {
		return EvidenceRecord{}, ErrRemoteIntegrity
	}
	record := EvidenceRecord{Request: req, ObjectURI: "s3://" + req.Bucket + "/" + key}
	if err := s.repo.PersistEvidenceAndOutbox(ctx, record); err != nil {
		return EvidenceRecord{}, fmt.Errorf("persist evidence and outbox: %w", err)
	}
	return record, nil
}

func validateRequest(req Request) error {
	if strings.TrimSpace(req.Bucket) == "" {
		return ErrEmptyBucket
	}
	if strings.TrimSpace(req.SourceSystem) == "" || strings.TrimSpace(req.SourceVersion) == "" || strings.TrimSpace(req.IdempotencyKey) == "" {
		return ErrRequest
	}
	if _, _, err := mime.ParseMediaType(req.MIMEType); err != nil {
		return ErrRequest
	}
	if _, err := time.Parse(time.RFC3339, req.SourceObservedAt); err != nil {
		return ErrRequest
	}
	if _, err := time.Parse(time.RFC3339, req.OccurredAt); err != nil {
		return ErrRequest
	}
	if _, err := uuid.Parse(req.EventID); err != nil {
		return ErrRequest
	}
	if _, err := uuid.Parse(req.CorrelationID); err != nil {
		return ErrRequest
	}
	if req.CausationID != "" {
		if _, err := uuid.Parse(req.CausationID); err != nil {
			return ErrRequest
		}
	}
	return nil
}
