package publisher

import (
	"context"
	"errors"
	"fmt"
	"time"
)

var ErrStaleClaim = errors.New("outbox claim token is no longer current")

type Message struct {
	OrganizationID string
	ID             string
	EventID        string
	Subject        string
	Envelope       []byte
	ClaimToken     string
}

type Store interface {
	Claim(context.Context, string, int, time.Time, time.Duration) ([]Message, error)
	MarkPublished(context.Context, Message, time.Time) (bool, error)
	RecordFailure(context.Context, Message, string, time.Time, int, time.Time) (string, error)
}

type Broker interface {
	Publish(context.Context, string, []byte, string) error
}

type Clock interface {
	Now() time.Time
}

type Config struct {
	WorkerID    string
	BatchSize   int
	Lease       time.Duration
	RetryDelay  time.Duration
	MaxAttempts int
}

type Publisher struct {
	store  Store
	broker Broker
	clock  Clock
	config Config
}

func New(store Store, broker Broker, clock Clock, config Config) (*Publisher, error) {
	if store == nil || broker == nil || clock == nil {
		return nil, errors.New("store, broker, and clock are required")
	}
	if config.WorkerID == "" || config.BatchSize < 1 || config.BatchSize > 1000 ||
		config.Lease <= 0 || config.RetryDelay < 0 || config.MaxAttempts < 1 {
		return nil, errors.New("invalid publisher configuration")
	}
	return &Publisher{store: store, broker: broker, clock: clock, config: config}, nil
}

func (p *Publisher) Tick(ctx context.Context) (int, error) {
	claimedAt := p.clock.Now().UTC()
	messages, err := p.store.Claim(
		ctx,
		p.config.WorkerID,
		p.config.BatchSize,
		claimedAt,
		p.config.Lease,
	)
	if err != nil {
		return 0, fmt.Errorf("claim outbox: %w", err)
	}

	processed := 0
	for _, message := range messages {
		if err := p.publishOne(ctx, message); err != nil {
			return processed, err
		}
		processed++
	}
	return processed, nil
}

func (p *Publisher) publishOne(ctx context.Context, message Message) error {
	if err := p.broker.Publish(ctx, message.Subject, message.Envelope, message.EventID); err != nil {
		failedAt := p.clock.Now().UTC()
		state, recordErr := p.store.RecordFailure(
			ctx,
			message,
			err.Error(),
			failedAt.Add(p.config.RetryDelay),
			p.config.MaxAttempts,
			failedAt,
		)
		if recordErr != nil {
			return fmt.Errorf("publish failed (%v), then failure CAS failed: %w", err, recordErr)
		}
		if state == "" {
			return fmt.Errorf("publish failed (%v): %w", err, ErrStaleClaim)
		}
		return fmt.Errorf("publish %s: %w", state, err)
	}

	published, err := p.store.MarkPublished(ctx, message, p.clock.Now().UTC())
	if err != nil {
		return fmt.Errorf("mark published: %w", err)
	}
	if !published {
		return ErrStaleClaim
	}
	return nil
}
