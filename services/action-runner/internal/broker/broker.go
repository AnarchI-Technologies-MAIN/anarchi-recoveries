// Package broker defines the narrow secret-resolution boundary for action
// execution. It returns an opaque lease capability, never secret material.
package broker

import (
	"context"
	"errors"
	"strings"
)

var (
	ErrInvalidRequest   = errors.New("invalid secret capability request")
	ErrAuthorization    = errors.New("secret capability authorization denied")
	ErrScopeMismatch    = errors.New("secret capability scope mismatch")
	ErrVaultUnavailable = errors.New("vault lease unavailable")
)

type SecretReference struct {
	ID             string `json:"secret_ref"`
	OrganizationID string `json:"organization_id"`
	Purpose        string `json:"purpose"`
	Provider       string `json:"provider"`
	Version        string `json:"version"`
}

type DecisionReceipt struct {
	Result         string `json:"result"`
	OrganizationID string `json:"organization_id"`
	Purpose        string `json:"purpose"`
	BindingID      string `json:"binding_id"`
	DecisionHash   string `json:"decision_hash"`
	ExpiresAt      string `json:"expires_at"`
}

type Request struct {
	Subject   string          `json:"subject"`
	Operation string          `json:"operation"`
	Purpose   string          `json:"purpose"`
	Reference SecretReference `json:"reference"`
	Decision  DecisionReceipt `json:"decision"`
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
		request.Decision.OrganizationID,
		request.Decision.Purpose,
		request.Decision.BindingID,
		request.Decision.DecisionHash,
		request.Decision.ExpiresAt,
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
