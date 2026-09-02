// Package broker defines the narrow secret-resolution boundary for action
// execution. It returns an opaque lease capability, never secret material.
package broker

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

var (
	ErrInvalidRequest      = errors.New("invalid secret capability request")
	ErrAuthorization       = errors.New("secret capability authorization denied")
	ErrScopeMismatch       = errors.New("secret capability scope mismatch")
	ErrVaultUnavailable    = errors.New("vault lease unavailable")
	ErrReceiptExpired      = errors.New("decision receipt has expired")
	ErrReceiptUnbound      = errors.New("decision receipt is not bound to this request")
	ErrReceiptInvalidHash  = errors.New("decision receipt hash is invalid")
	ErrReceiptMissingField = errors.New("decision receipt is missing required field")
)

type SecretReference struct {
	ID             string `json:"secret_ref"`
	OrganizationID string `json:"organization_id"`
	Purpose        string `json:"purpose"`
	Provider       string `json:"provider"`
	Version        string `json:"version"`
}

type DecisionReceipt struct {
	Canonicalization string `json:"canonicalization"`
	DecisionID       string `json:"decision_id"`
	Subject          string `json:"subject"`
	OrganizationID   string `json:"organization_id"`
	Operation        string `json:"operation"`
	Resource         string `json:"resource"`
	Purpose          string `json:"purpose"`
	Result           string `json:"result"`
	AuthorityClass   string `json:"authority_class"`
	PolicyVersion    string `json:"policy_version"`
	BindingID        string `json:"binding_id"`
	ExpiresAt        string `json:"expires_at"`
	PayloadHash      string `json:"payload_hash"`
	DecisionHash     string `json:"decision_hash"`
}

type Request struct {
	Subject     string          `json:"subject"`
	Operation   string          `json:"operation"`
	Purpose     string          `json:"purpose"`
	Reference   SecretReference `json:"reference"`
	Decision    DecisionReceipt `json:"decision"`
	PayloadHash string          `json:"payload_hash"`
}

type Lease struct {
	ID        string
	ExpiresAt string
}

type Capability struct {
	LeaseID        string `json:"lease_id"`
	SecretRef      string `json:"secret_ref"`
	OrganizationID string `json:"organization_id"`
	Purpose        string `json:"purpose"`
	Operation      string `json:"operation"`
	ExpiresAt      string `json:"expires_at"`
}

type Vault interface {
	IssueLease(context.Context, SecretReference, string) (Lease, error)
}

type Broker struct {
	vault Vault
}

func New(vault Vault) (*Broker, error) {
	if vault == nil {
		return nil, ErrVaultUnavailable
	}
	return &Broker{vault: vault}, nil
}

func (b *Broker) Resolve(ctx context.Context, request Request) (Capability, error) {
	if err := validateRequest(request); err != nil {
		return Capability{}, err
	}
	if err := verifyReceipt(request); err != nil {
		return Capability{}, err
	}
	if request.Decision.Result != "ALLOW" {
		return Capability{}, ErrAuthorization
	}
	if request.Decision.OrganizationID != request.Reference.OrganizationID ||
		request.Decision.Purpose != request.Purpose ||
		request.Reference.Purpose != request.Purpose {
		return Capability{}, ErrScopeMismatch
	}
	lease, err := b.vault.IssueLease(ctx, request.Reference, request.Operation)
	if err != nil {
		return Capability{}, errors.Join(ErrVaultUnavailable, err)
	}
	if strings.TrimSpace(lease.ID) == "" || strings.TrimSpace(lease.ExpiresAt) == "" {
		return Capability{}, ErrVaultUnavailable
	}
	return Capability{
		LeaseID:        lease.ID,
		SecretRef:      request.Reference.ID,
		OrganizationID: request.Reference.OrganizationID,
		Purpose:        request.Purpose,
		Operation:      request.Operation,
		ExpiresAt:      lease.ExpiresAt,
	}, nil
}

func validateRequest(request Request) error {
	for _, value := range []string{
		request.Subject,
		request.Operation,
		request.Purpose,
		request.Reference.ID,
		request.Reference.OrganizationID,
		request.Reference.Purpose,
		request.Reference.Provider,
		request.Reference.Version,
		request.Decision.Canonicalization,
		request.Decision.DecisionID,
		request.Decision.Subject,
		request.Decision.OrganizationID,
		request.Decision.Operation,
		request.Decision.Resource,
		request.Decision.Purpose,
		request.Decision.AuthorityClass,
		request.Decision.PolicyVersion,
		request.Decision.BindingID,
		request.Decision.DecisionHash,
		request.Decision.ExpiresAt,
		request.Decision.PayloadHash,
	} {
		if strings.TrimSpace(value) == "" {
			return ErrInvalidRequest
		}
	}
	if request.Decision.Result != "ALLOW" && request.Decision.Result != "DENY" {
		return ErrInvalidRequest
	}
	return nil
}

// verifyReceipt cryptographically verifies the decision receipt and binds it to the request.
func verifyReceipt(request Request) error {
	receipt := request.Decision

	// Verify receipt is bound to the request subject
	if receipt.Subject != request.Subject {
		return ErrReceiptUnbound
	}

	// Verify receipt is bound to the request operation
	if receipt.Operation != request.Operation {
		return ErrReceiptUnbound
	}

	// Verify receipt is bound to the request resource (secret reference ID)
	if receipt.Resource != request.Reference.ID {
		return ErrReceiptUnbound
	}

	// Verify receipt is bound to the request purpose
	if receipt.Purpose != request.Purpose {
		return ErrReceiptUnbound
	}

	// Verify receipt is bound to the request payload hash
	if request.PayloadHash != "" && receipt.PayloadHash != request.PayloadHash {
		return ErrReceiptUnbound
	}

	// Verify receipt has not expired
	expiresAt, err := time.Parse(time.RFC3339, receipt.ExpiresAt)
	if err != nil {
		return ErrReceiptExpired
	}
	if time.Now().After(expiresAt) {
		return ErrReceiptExpired
	}

	// Verify the decision hash cryptographically
	if err := verifyDecisionHash(receipt); err != nil {
		return err
	}

	return nil
}

// unsignedReceipt represents the canonical structure for hash computation.
type unsignedReceipt struct {
	Canonicalization string `json:"canonicalization"`
	DecisionID       string `json:"decision_id"`
	Subject          string `json:"subject"`
	OrganizationID   string `json:"organization_id"`
	Operation        string `json:"operation"`
	Resource         string `json:"resource"`
	Purpose          string `json:"purpose"`
	Result           string `json:"result"`
	AuthorityClass   string `json:"authority_class"`
	PolicyVersion    string `json:"policy_version"`
	BindingID        string `json:"binding_id"`
	ExpiresAt        string `json:"expires_at"`
	PayloadHash      string `json:"payload_hash"`
}

// verifyDecisionHash verifies the cryptographic integrity of the decision receipt.
func verifyDecisionHash(receipt DecisionReceipt) error {
	// Reconstruct the unsigned receipt for hash verification
	unsigned := unsignedReceipt{
		Canonicalization: receipt.Canonicalization,
		DecisionID:       receipt.DecisionID,
		Subject:          receipt.Subject,
		OrganizationID:   receipt.OrganizationID,
		Operation:        receipt.Operation,
		Resource:         receipt.Resource,
		Purpose:          receipt.Purpose,
		Result:           receipt.Result,
		AuthorityClass:   receipt.AuthorityClass,
		PolicyVersion:    receipt.PolicyVersion,
		BindingID:        receipt.BindingID,
		ExpiresAt:        receipt.ExpiresAt,
		PayloadHash:      receipt.PayloadHash,
	}

	// Compute canonical hash
	canonical, err := json.Marshal(unsigned)
	if err != nil {
		return ErrReceiptInvalidHash
	}

	hash := sha256.Sum256(canonical)
	computedHash := "sha256:" + hex.EncodeToString(hash[:])

	// Verify the hash matches
	if computedHash != receipt.DecisionHash {
		return ErrReceiptInvalidHash
	}

	return nil
}
