package repository

import (
	"context"
	"fmt"

	"anarchi.tech/recoveries/ingestion/internal/ingest"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Postgres struct {
	pool *pgxpool.Pool
}

func NewPostgres(pool *pgxpool.Pool) (*Postgres, error) {
	if pool == nil {
		return nil, fmt.Errorf("postgres pool is required")
	}
	return &Postgres{pool: pool}, nil
}

func (p *Postgres) PersistEvidenceAndOutbox(ctx context.Context, record ingest.EvidenceRecord) error {
	tx, err := p.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return fmt.Errorf("begin ingestion transaction: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, "SELECT set_config('anarchi.current_organization_id', $1, true)", record.Identity.OrganizationID); err != nil {
		return fmt.Errorf("set organization context: %w", err)
	}

	var causation any
	if record.CausationID != "" {
		causation = record.CausationID
	}
	var persistedID string
	err = tx.QueryRow(ctx, `
		SELECT recoveries.persist_ingested_evidence(
			$1, $2, $3, $4, nullif($5, ''), $6, $7, $8, $9,
			$10, $11, $12, '{}'::jsonb, $13, $14, $15, $16, $17
		)::text`,
		record.Identity.OrganizationID, record.Identity.ProjectID, record.Identity.EvidenceID,
		record.SourceSystem, record.ExternalID, record.SourceVersion, record.SourceObservedAt,
		record.ObjectURI, record.Identity.Filename, record.MIMEType, record.SizeBytes,
		record.Identity.SHA256, record.EventID, record.OccurredAt, causation,
		record.CorrelationID, record.IdempotencyKey,
	).Scan(&persistedID)
	if err != nil {
		return fmt.Errorf("persist ingested evidence: %w", err)
	}
	if persistedID != record.Identity.EvidenceID {
		return fmt.Errorf("persisted evidence id mismatch")
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit ingestion transaction: %w", err)
	}
	return nil
}
