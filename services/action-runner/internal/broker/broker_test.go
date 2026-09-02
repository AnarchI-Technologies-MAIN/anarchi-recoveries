package broker

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"
)

type vaultFake struct {
	lease Lease
	err   error
}

func (f vaultFake) IssueLease(context.Context, SecretReference, string) (Lease, error) {
	return f.lease, f.err
}

func validReceipt(subject, operation, resource, purpose, payloadHash string) DecisionReceipt {
	expiresAt := time.Now().Add(24 * time.Hour).Format(time.RFC3339)
	unsigned := unsignedReceipt{
		Canonicalization: "v1",
		DecisionID:       "decision-1",
		Subject:          subject,
		OrganizationID:   "org-1",
		Operation:        operation,
		Resource:         resource,
		Purpose:          purpose,
		Result:           "ALLOW",
		AuthorityClass:   "RECOVERIES_AUTH",
		PolicyVersion:    "RECOVERIES_AUTH_V1",
		BindingID:        "ENF-RECOVERIES-00001",
		ExpiresAt:        expiresAt,
		PayloadHash:      payloadHash,
	}
	canonical, _ := json.Marshal(unsigned)
	hash := sha256.Sum256(canonical)
	decisionHash := "sha256:" + hex.EncodeToString(hash[:])

	return DecisionReceipt{
		Canonicalization: unsigned.Canonicalization,
		DecisionID:       unsigned.DecisionID,
		Subject:          unsigned.Subject,
		OrganizationID:   unsigned.OrganizationID,
		Operation:        unsigned.Operation,
		Resource:         unsigned.Resource,
		Purpose:          unsigned.Purpose,
		Result:           unsigned.Result,
		AuthorityClass:   unsigned.AuthorityClass,
		PolicyVersion:    unsigned.PolicyVersion,
		BindingID:        unsigned.BindingID,
		ExpiresAt:        unsigned.ExpiresAt,
		PayloadHash:      unsigned.PayloadHash,
		DecisionHash:     decisionHash,
	}
}

func request() Request {
	payloadHash := "sha256:payload-1"
	return Request{
		Subject:     "action-runner-1",
		Operation:   "submit_external_notice",
		Purpose:     "recovery_notice",
		PayloadHash: payloadHash,
		Reference: SecretReference{
			ID: "secret-ref-1", OrganizationID: "org-1", Purpose: "recovery_notice",
			Provider: "procore", Version: "v1",
		},
		Decision: validReceipt("action-runner-1", "submit_external_notice", "secret-ref-1", "recovery_notice", payloadHash),
	}
}

func TestResolveReturnsOpaqueScopedCapability(t *testing.T) {
	b, err := New(vaultFake{lease: Lease{ID: "lease-1", ExpiresAt: "2026-08-29T01:00:00Z"}})
	if err != nil {
		t.Fatal(err)
	}
	capability, err := b.Resolve(context.Background(), request())
	if err != nil {
		t.Fatal(err)
	}
	if capability.LeaseID != "lease-1" || capability.SecretRef != "secret-ref-1" || capability.OrganizationID != "org-1" {
		t.Fatalf("unexpected capability: %+v", capability)
	}
	wire, err := json.Marshal(capability)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(wire), "secret_material") || strings.Contains(string(wire), "access_token") {
		t.Fatalf("capability leaked secret material: %s", wire)
	}
}

func TestMissingApprovalIsDeniedBeforeVault(t *testing.T) {
	b, _ := New(vaultFake{lease: Lease{ID: "lease-1", ExpiresAt: "future"}})
	value := request()
	value.Decision.Result = "DENY"
	_, err := b.Resolve(context.Background(), value)
	if !errors.Is(err, ErrAuthorization) {
		t.Fatalf("expected authorization denial, got %v", err)
	}
}

func TestWrongPurposeIsDenied(t *testing.T) {
	b, _ := New(vaultFake{lease: Lease{ID: "lease-1", ExpiresAt: "future"}})
	value := request()
	value.Purpose = "different_purpose"
	_, err := b.Resolve(context.Background(), value)
	if !errors.Is(err, ErrScopeMismatch) {
		t.Fatalf("expected scope mismatch, got %v", err)
	}
}

func TestRevokedVaultLeaseFailsClosed(t *testing.T) {
	b, _ := New(vaultFake{err: errors.New("revoked")})
	_, err := b.Resolve(context.Background(), request())
	if !errors.Is(err, ErrVaultUnavailable) {
		t.Fatalf("expected vault failure, got %v", err)
	}
}

func TestBlankLeaseFailsClosed(t *testing.T) {
	b, _ := New(vaultFake{lease: Lease{ID: "", ExpiresAt: "future"}})
	_, err := b.Resolve(context.Background(), request())
	if !errors.Is(err, ErrVaultUnavailable) {
		t.Fatalf("expected invalid lease failure, got %v", err)
	}
}

func TestReceiptMustBindToSubject(t *testing.T) {
	b, _ := New(vaultFake{lease: Lease{ID: "lease-1", ExpiresAt: "future"}})
	value := request()
	value.Subject = "different-subject"
	_, err := b.Resolve(context.Background(), value)
	if !errors.Is(err, ErrReceiptUnbound) {
		t.Fatalf("expected receipt unbound error, got %v", err)
	}
}

func TestReceiptMustBindToOperation(t *testing.T) {
	b, _ := New(vaultFake{lease: Lease{ID: "lease-1", ExpiresAt: "future"}})
	value := request()
	value.Operation = "different_operation"
	_, err := b.Resolve(context.Background(), value)
	if !errors.Is(err, ErrReceiptUnbound) {
		t.Fatalf("expected receipt unbound error, got %v", err)
	}
}

func TestReceiptMustBindToResource(t *testing.T) {
	b, _ := New(vaultFake{lease: Lease{ID: "lease-1", ExpiresAt: "future"}})
	value := request()
	value.Reference.ID = "different-secret-ref"
	_, err := b.Resolve(context.Background(), value)
	if !errors.Is(err, ErrReceiptUnbound) {
		t.Fatalf("expected receipt unbound error, got %v", err)
	}
}

func TestReceiptMustBindToPayloadHash(t *testing.T) {
	b, _ := New(vaultFake{lease: Lease{ID: "lease-1", ExpiresAt: "future"}})
	value := request()
	value.PayloadHash = "sha256:different-payload"
	_, err := b.Resolve(context.Background(), value)
	if !errors.Is(err, ErrReceiptUnbound) {
		t.Fatalf("expected receipt unbound error, got %v", err)
	}
}

func TestExpiredReceiptIsRejected(t *testing.T) {
	b, _ := New(vaultFake{lease: Lease{ID: "lease-1", ExpiresAt: "future"}})
	value := request()
	// Create an expired receipt
	expiredTime := time.Now().Add(-24 * time.Hour).Format(time.RFC3339)
	payloadHash := "sha256:payload-1"
	unsigned := unsignedReceipt{
		Canonicalization: "v1",
		DecisionID:       "decision-1",
		Subject:          "action-runner-1",
		OrganizationID:   "org-1",
		Operation:        "submit_external_notice",
		Resource:         "secret-ref-1",
		Purpose:          "recovery_notice",
		Result:           "ALLOW",
		AuthorityClass:   "RECOVERIES_AUTH",
		PolicyVersion:    "RECOVERIES_AUTH_V1",
		BindingID:        "ENF-RECOVERIES-00001",
		ExpiresAt:        expiredTime,
		PayloadHash:      payloadHash,
	}
	canonical, _ := json.Marshal(unsigned)
	hash := sha256.Sum256(canonical)
	value.Decision = DecisionReceipt{
		Canonicalization: unsigned.Canonicalization,
		DecisionID:       unsigned.DecisionID,
		Subject:          unsigned.Subject,
		OrganizationID:   unsigned.OrganizationID,
		Operation:        unsigned.Operation,
		Resource:         unsigned.Resource,
		Purpose:          unsigned.Purpose,
		Result:           unsigned.Result,
		AuthorityClass:   unsigned.AuthorityClass,
		PolicyVersion:    unsigned.PolicyVersion,
		BindingID:        unsigned.BindingID,
		ExpiresAt:        unsigned.ExpiresAt,
		PayloadHash:      unsigned.PayloadHash,
		DecisionHash:     "sha256:" + hex.EncodeToString(hash[:]),
	}
	_, err := b.Resolve(context.Background(), value)
	if !errors.Is(err, ErrReceiptExpired) {
		t.Fatalf("expected receipt expired error, got %v", err)
	}
}

func TestTamperedHashIsRejected(t *testing.T) {
	b, _ := New(vaultFake{lease: Lease{ID: "lease-1", ExpiresAt: "future"}})
	value := request()
	// Tamper with the decision hash
	value.Decision.DecisionHash = "sha256:" + strings.Repeat("f", 64)
	_, err := b.Resolve(context.Background(), value)
	if !errors.Is(err, ErrReceiptInvalidHash) {
		t.Fatalf("expected invalid hash error, got %v", err)
	}
}

func TestTamperedFieldIsRejected(t *testing.T) {
	b, _ := New(vaultFake{lease: Lease{ID: "lease-1", ExpiresAt: "future"}})
	value := request()
	// Tamper with a field after the hash was computed
	value.Decision.Resource = "different-resource"
	_, err := b.Resolve(context.Background(), value)
	if !errors.Is(err, ErrReceiptInvalidHash) {
		t.Fatalf("expected invalid hash error, got %v", err)
	}
}

func TestForgedReceiptWithMatchingOrgIsRejected(t *testing.T) {
	b, _ := New(vaultFake{lease: Lease{ID: "lease-1", ExpiresAt: "future"}})
	value := request()
	// Attempt to forge a receipt for a different resource with matching org
	forgedReceipt := validReceipt("action-runner-1", "submit_external_notice", "different-secret", "recovery_notice", "sha256:payload-1")
	value.Decision = forgedReceipt
	_, err := b.Resolve(context.Background(), value)
	if !errors.Is(err, ErrReceiptUnbound) {
		t.Fatalf("expected receipt unbound error for forged receipt, got %v", err)
	}
}

func TestReusedReceiptForDifferentOperationIsRejected(t *testing.T) {
	b, _ := New(vaultFake{lease: Lease{ID: "lease-1", ExpiresAt: "future"}})
	value := request()
	// Attempt to reuse a receipt for a different operation
	value.Operation = "read_secret"
	_, err := b.Resolve(context.Background(), value)
	if !errors.Is(err, ErrReceiptUnbound) {
		t.Fatalf("expected receipt unbound error for reused receipt, got %v", err)
	}
}
