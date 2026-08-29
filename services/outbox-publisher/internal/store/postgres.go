package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"anarchi.tech/recoveries/outbox-publisher/internal/publisher"
)

type Postgres struct {
	pool           *pgxpool.Pool
	organizationID uuid.UUID
}

func NewPostgres(pool *pgxpool.Pool, organizationID uuid.UUID) (*Postgres, error) {
	if pool == nil || organizationID == uuid.Nil {
		return nil, errors.New("pool and organization ID are required")
	}
	return &Postgres{pool: pool, organizationID: organizationID}, nil
}

func (store *Postgres) withTenantTx(
	ctx context.Context,
	operation func(pgx.Tx) error,
) error {
	tx, err := store.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(
		ctx,
		"SELECT set_config('anarchi.current_organization_id', $1, true)",
		store.organizationID.String(),
	); err != nil {
		return err
	}
	if err := operation(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (store *Postgres) Claim(
	ctx context.Context,
	workerID string,
	batchSize int,
	now time.Time,
	lease time.Duration,
) ([]publisher.Message, error) {
	messages := make([]publisher.Message, 0, batchSize)
	err := store.withTenantTx(ctx, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT organization_id::text, id::text, event_id::text, subject,
			       envelope::text, claim_token::text
			FROM recoveries.claim_outbox($1, $2, $3, $4)
			ORDER BY available_at, id
		`, workerID, batchSize, now, lease)
		if err != nil {
			return err
		}
		defer rows.Close()

		for rows.Next() {
			var message publisher.Message
			if err := rows.Scan(
				&message.OrganizationID,
				&message.ID,
				&message.EventID,
				&message.Subject,
				&message.Envelope,
				&message.ClaimToken,
			); err != nil {
				return err
			}
			messages = append(messages, message)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("claim transaction: %w", err)
	}
	return messages, nil
}

func (store *Postgres) MarkPublished(
	ctx context.Context,
	message publisher.Message,
	publishedAt time.Time,
) (bool, error) {
	var published bool
	err := store.withTenantTx(ctx, func(tx pgx.Tx) error {
		return tx.QueryRow(
			ctx,
			"SELECT recoveries.mark_outbox_published($1, $2, $3, $4)",
			message.OrganizationID,
			message.ID,
			message.ClaimToken,
			publishedAt,
		).Scan(&published)
	})
	return published, err
}

func (store *Postgres) RecordFailure(
	ctx context.Context,
	message publisher.Message,
	publishError string,
	retryAt time.Time,
	maxAttempts int,
	failedAt time.Time,
) (string, error) {
	var state *string
	err := store.withTenantTx(ctx, func(tx pgx.Tx) error {
		return tx.QueryRow(
			ctx,
			"SELECT recoveries.record_outbox_publish_failure($1, $2, $3, $4, $5, $6, $7)",
			message.OrganizationID,
			message.ID,
			message.ClaimToken,
			publishError,
			retryAt,
			maxAttempts,
			failedAt,
		).Scan(&state)
	})
	if err != nil || state == nil {
		return "", err
	}
	return *state, nil
}
