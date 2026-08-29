package broker

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

type vaultFake struct {
	lease Lease
	err   error
}

func (f vaultFake) IssueLease(context.Context, SecretReference, string) (Lease, error) {
	return f.lease, f.err
}

func request() Request {
	return Request{
		Subject: "action-runner-1", Operation: "submit_external_notice", Purpose: "recovery_notice",
		Reference: SecretReference{
			ID: "secret-ref-1", OrganizationID: "org-1", Purpose: "recovery_notice",
			Provider: "procore", Version: "v1",
		},
		Decision: DecisionReceipt{
			Result: "ALLOW", OrganizationID: "org-1", Purpose: "recovery_notice",
			BindingID: "ENF-RECOVERIES-00001", DecisionHash: strings.Repeat("a", 64),
			ExpiresAt: "2026-08-30T00:00:00Z",
		},
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
