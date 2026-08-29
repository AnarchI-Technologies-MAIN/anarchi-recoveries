package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/nats-io/nats.go"

	"anarchi.tech/recoveries/outbox-publisher/internal/broker"
	"anarchi.tech/recoveries/outbox-publisher/internal/publisher"
	"anarchi.tech/recoveries/outbox-publisher/internal/store"
)

type systemClock struct{}

func (systemClock) Now() time.Time { return time.Now() }

func requiredEnv(name string) (string, error) {
	value := os.Getenv(name)
	if value == "" {
		return "", fmt.Errorf("%s is required", name)
	}
	return value, nil
}

func positiveIntEnv(name string) (int, error) {
	raw, err := requiredEnv(name)
	if err != nil {
		return 0, err
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value < 1 {
		return 0, fmt.Errorf("%s must be a positive integer", name)
	}
	return value, nil
}

func run(ctx context.Context) error {
	databaseURL, err := requiredEnv("RECOVERIES_DATABASE_URL")
	if err != nil {
		return err
	}
	natsURL, err := requiredEnv("RECOVERIES_NATS_URL")
	if err != nil {
		return err
	}
	workerID, err := requiredEnv("RECOVERIES_OUTBOX_WORKER_ID")
	if err != nil {
		return err
	}
	organizationRaw, err := requiredEnv("RECOVERIES_ORGANIZATION_ID")
	if err != nil {
		return err
	}
	organizationID, err := uuid.Parse(organizationRaw)
	if err != nil {
		return fmt.Errorf("RECOVERIES_ORGANIZATION_ID: %w", err)
	}
	batchSize, err := positiveIntEnv("RECOVERIES_OUTBOX_BATCH_SIZE")
	if err != nil {
		return err
	}
	maxAttempts, err := positiveIntEnv("RECOVERIES_OUTBOX_MAX_ATTEMPTS")
	if err != nil {
		return err
	}

	poolConfig, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return err
	}
	poolConfig.AfterConnect = func(ctx context.Context, connection *pgx.Conn) error {
		_, err := connection.Exec(ctx, "SET ROLE recoveries_outbox_publisher_role")
		return err
	}
	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return err
	}
	defer pool.Close()

	natsConnection, err := nats.Connect(natsURL, nats.Name("recoveries-outbox-publisher"))
	if err != nil {
		return err
	}
	defer natsConnection.Close()

	natsBroker, err := broker.NewNATS(natsConnection)
	if err != nil {
		return err
	}
	postgresStore, err := store.NewPostgres(pool, organizationID)
	if err != nil {
		return err
	}
	service, err := publisher.New(postgresStore, natsBroker, systemClock{}, publisher.Config{
		WorkerID:    workerID,
		BatchSize:   batchSize,
		Lease:       30 * time.Second,
		RetryDelay:  time.Minute,
		MaxAttempts: maxAttempts,
	})
	if err != nil {
		return err
	}

	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			processed, err := service.Tick(ctx)
			if err != nil && !errors.Is(err, context.Canceled) {
				slog.Error("outbox tick failed", "error", err)
				continue
			}
			if processed > 0 {
				slog.Info("outbox batch published", "count", processed)
			}
		}
	}
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	if err := run(ctx); err != nil {
		slog.Error("outbox publisher stopped", "error", err)
		os.Exit(1)
	}
}
