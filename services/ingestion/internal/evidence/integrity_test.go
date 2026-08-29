package evidence

import (
	"errors"
	"strings"
	"testing"
)

const (
	proofBody = "AnarchI evidence proof bytes\n"
	proofHash = "ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658"
)

func proofIdentity() Identity {
	return Identity{
		OrganizationID: "00000000-0000-4000-8000-000000001101",
		ProjectID:      "00000000-0000-4000-8000-000000001102",
		EvidenceID:     "00000000-0000-4000-8000-000000001103",
		SHA256:         proofHash,
		Filename:       "source.bin",
	}
}

func TestObjectKeyIsCanonical(t *testing.T) {
	got, err := ObjectKey(proofIdentity())
	if err != nil {
		t.Fatal(err)
	}
	want := "org/00000000-0000-4000-8000-000000001101/project/00000000-0000-4000-8000-000000001102/evidence/00000000-0000-4000-8000-000000001103/" + proofHash + "/source.bin"
	if got != want {
		t.Fatalf("key mismatch: got %q want %q", got, want)
	}
}

func TestObjectKeyRejectsTraversal(t *testing.T) {
	v := proofIdentity()
	v.Filename = "../source.bin"
	if _, err := ObjectKey(v); !errors.Is(err, ErrIdentity) {
		t.Fatalf("expected ErrIdentity, got %v", err)
	}
}

func TestVerifyAcceptsExactBytes(t *testing.T) {
	if err := Verify(strings.NewReader(proofBody), proofHash, int64(len(proofBody))); err != nil {
		t.Fatal(err)
	}
}

func TestVerifyRejectsHashMismatch(t *testing.T) {
	err := Verify(strings.NewReader(proofBody+"tampered"), proofHash, int64(len(proofBody)+8))
	if !errors.Is(err, ErrHash) {
		t.Fatalf("expected ErrHash, got %v", err)
	}
}

func TestVerifyRejectsSizeMismatch(t *testing.T) {
	err := Verify(strings.NewReader(proofBody), proofHash, int64(len(proofBody)+1))
	if !errors.Is(err, ErrSize) {
		t.Fatalf("expected ErrSize, got %v", err)
	}
}
