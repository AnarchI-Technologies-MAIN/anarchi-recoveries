package publisher

import (
	"context"
	"errors"
	"testing"
	"time"
)

type fixedClock struct{ now time.Time }

func (clock *fixedClock) Now() time.Time {
	result := clock.now
	clock.now = clock.now.Add(time.Second)
	return result
}

type fakeStore struct {
	messages     []Message
	marked       []Message
	failed       []Message
	failureState string
	markCurrent  bool
}

func (store *fakeStore) Claim(
	context.Context,
	string,
	int,
	time.Time,
	time.Duration,
) ([]Message, error) {
	return store.messages, nil
}

func (store *fakeStore) MarkPublished(
	_ context.Context,
	message Message,
	_ time.Time,
) (bool, error) {
	store.marked = append(store.marked, message)
	return store.markCurrent, nil
}

func (store *fakeStore) RecordFailure(
	_ context.Context,
	message Message,
	_ string,
	_ time.Time,
	_ int,
	_ time.Time,
) (string, error) {
	store.failed = append(store.failed, message)
	return store.failureState, nil
}

type fakeBroker struct {
	published []Message
	err       error
}

func (broker *fakeBroker) Publish(
	_ context.Context,
	subject string,
	envelope []byte,
	eventID string,
) error {
	broker.published = append(broker.published, Message{
		Subject:  subject,
		Envelope: envelope,
		EventID:  eventID,
	})
	return broker.err
}

func testConfig() Config {
	return Config{
		WorkerID:    "worker-proof",
		BatchSize:   10,
		Lease:       30 * time.Second,
		RetryDelay:  time.Minute,
		MaxAttempts: 3,
	}
}

func TestSuccessfulPublishUsesEventIDAndThenCAS(t *testing.T) {
	message := Message{
		OrganizationID: "org",
		ID:             "outbox",
		EventID:        "event",
		Subject:        "fact.verified.v1",
		Envelope:       []byte(`{"schema_version":"1.0"}`),
		ClaimToken:     "claim",
	}
	store := &fakeStore{messages: []Message{message}, markCurrent: true}
	broker := &fakeBroker{}
	clock := &fixedClock{now: time.Date(2026, 8, 29, 0, 0, 0, 0, time.UTC)}
	service, err := New(store, broker, clock, testConfig())
	if err != nil {
		t.Fatal(err)
	}

	processed, err := service.Tick(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if processed != 1 || len(broker.published) != 1 || len(store.marked) != 1 {
		t.Fatalf("unexpected success counts: processed=%d published=%d marked=%d", processed, len(broker.published), len(store.marked))
	}
	if broker.published[0].EventID != message.EventID || broker.published[0].Subject != message.Subject {
		t.Fatal("broker did not receive the canonical event identity and subject")
	}
	if len(store.failed) != 0 {
		t.Fatal("success path recorded a failure")
	}
}

func TestBrokerFailureRecordsActualAttemptWithoutSuccessCAS(t *testing.T) {
	message := Message{EventID: "event", Subject: "fact.verified.v1", ClaimToken: "claim"}
	store := &fakeStore{messages: []Message{message}, failureState: "PENDING"}
	broker := &fakeBroker{err: errors.New("broker unavailable")}
	clock := &fixedClock{now: time.Date(2026, 8, 29, 0, 0, 0, 0, time.UTC)}
	service, err := New(store, broker, clock, testConfig())
	if err != nil {
		t.Fatal(err)
	}

	processed, err := service.Tick(context.Background())
	if err == nil || processed != 0 {
		t.Fatalf("expected broker failure before processed count, got processed=%d err=%v", processed, err)
	}
	if len(store.failed) != 1 || len(store.marked) != 0 {
		t.Fatalf("failure path mismatch: failed=%d marked=%d", len(store.failed), len(store.marked))
	}
}

func TestStaleSuccessClaimIsExplicit(t *testing.T) {
	store := &fakeStore{
		messages:    []Message{{EventID: "event", Subject: "fact.verified.v1", ClaimToken: "old"}},
		markCurrent: false,
	}
	service, err := New(
		store,
		&fakeBroker{},
		&fixedClock{now: time.Date(2026, 8, 29, 0, 0, 0, 0, time.UTC)},
		testConfig(),
	)
	if err != nil {
		t.Fatal(err)
	}

	_, err = service.Tick(context.Background())
	if !errors.Is(err, ErrStaleClaim) {
		t.Fatalf("expected stale claim error, got %v", err)
	}
}
