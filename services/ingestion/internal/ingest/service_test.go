package ingest

import (
	"context"
	"errors"
	"testing"

	"anarchi.tech/recoveries/ingestion/internal/evidence"
)

const (
	proofBody = "AnarchI evidence proof bytes\n"
	proofHash = "ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658"
)

type objectFake struct {
	putCalls  int
	headCalls int
	head      ObjectMetadata
	putErr    error
	headErr   error
}

func (f *objectFake) PutIfAbsent(context.Context, string, string, []byte, ObjectMetadata) error {
	f.putCalls++
	return f.putErr
}

func (f *objectFake) Head(context.Context, string, string) (ObjectMetadata, error) {
	f.headCalls++
	return f.head, f.headErr
}

type repoFake struct {
	calls  int
	record EvidenceRecord
	err    error
}

func (f *repoFake) PersistEvidenceAndOutbox(_ context.Context, record EvidenceRecord) error {
	f.calls++
	f.record = record
	return f.err
}

func proofRequest() Request {
	return Request{
		Identity: evidence.Identity{
			OrganizationID: "00000000-0000-4000-8000-000000001101",
			ProjectID:      "00000000-0000-4000-8000-000000001102",
			EvidenceID:     "00000000-0000-4000-8000-000000001103",
			SHA256:         proofHash,
			Filename:       "source.bin",
		},
		Bucket: "recoveries-proof", SizeBytes: int64(len(proofBody)), Body: []byte(proofBody),
		SourceSystem: "file-upload", SourceVersion: "1", SourceObservedAt: "2026-08-29T00:00:00Z",
		MIMEType: "application/octet-stream", IdempotencyKey: "proof",
		EventID: "00000000-0000-4000-8000-000000001104", CorrelationID: "00000000-0000-4000-8000-000000001105",
		OccurredAt: "2026-08-29T00:00:01Z",
	}
}

func TestInvalidMetadataMutatesNothing(t *testing.T) {
	req := proofRequest()
	req.EventID = "not-a-uuid"
	objects := &objectFake{}
	repo := &repoFake{}
	service, _ := New(objects, repo)
	_, err := service.Ingest(context.Background(), req)
	if !errors.Is(err, ErrRequest) || objects.putCalls != 0 || repo.calls != 0 {
		t.Fatalf("expected invalid request before mutation, err=%v put=%d repo=%d", err, objects.putCalls, repo.calls)
	}
}

func TestIngestVerifiesRemoteBeforePersistence(t *testing.T) {
	req := proofRequest()
	metadata := ObjectMetadata{SHA256: proofHash, Filename: "source.bin", Size: int64(len(proofBody))}
	objects := &objectFake{head: metadata}
	repo := &repoFake{}
	service, _ := New(objects, repo)
	record, err := service.Ingest(context.Background(), req)
	if err != nil {
		t.Fatal(err)
	}
	if objects.putCalls != 1 || objects.headCalls != 1 || repo.calls != 1 {
		t.Fatalf("unexpected calls: put=%d head=%d repo=%d", objects.putCalls, objects.headCalls, repo.calls)
	}
	if record.ObjectURI != "s3://recoveries-proof/org/00000000-0000-4000-8000-000000001101/project/00000000-0000-4000-8000-000000001102/evidence/00000000-0000-4000-8000-000000001103/"+proofHash+"/source.bin" {
		t.Fatalf("unexpected object URI %q", record.ObjectURI)
	}
}

func TestHashMismatchMutatesNothing(t *testing.T) {
	req := proofRequest()
	req.Body = append(req.Body, 'x')
	objects := &objectFake{}
	repo := &repoFake{}
	service, _ := New(objects, repo)
	_, err := service.Ingest(context.Background(), req)
	if !errors.Is(err, evidence.ErrSize) || objects.putCalls != 0 || repo.calls != 0 {
		t.Fatalf("expected fail-closed size mismatch, err=%v put=%d repo=%d", err, objects.putCalls, repo.calls)
	}
}

func TestRemoteMismatchDoesNotPersist(t *testing.T) {
	objects := &objectFake{head: ObjectMetadata{SHA256: proofHash, Filename: "source.bin", Size: 1}}
	repo := &repoFake{}
	service, _ := New(objects, repo)
	_, err := service.Ingest(context.Background(), proofRequest())
	if !errors.Is(err, ErrRemoteIntegrity) || repo.calls != 0 {
		t.Fatalf("expected remote integrity failure, err=%v repo=%d", err, repo.calls)
	}
}

func TestPersistenceFailureIsExplicit(t *testing.T) {
	metadata := ObjectMetadata{SHA256: proofHash, Filename: "source.bin", Size: int64(len(proofBody))}
	objects := &objectFake{head: metadata}
	repo := &repoFake{err: errors.New("database unavailable")}
	service, _ := New(objects, repo)
	_, err := service.Ingest(context.Background(), proofRequest())
	if err == nil || repo.calls != 1 {
		t.Fatalf("expected explicit persistence failure, err=%v repo=%d", err, repo.calls)
	}
}
