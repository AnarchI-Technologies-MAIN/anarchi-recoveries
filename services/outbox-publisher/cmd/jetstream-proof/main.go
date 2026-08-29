package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"

	"anarchi.tech/recoveries/outbox-publisher/internal/broker"
)

func main() {
	natsURL := os.Getenv("RECOVERIES_TEST_NATS_URL")
	if natsURL == "" {
		fmt.Fprintln(os.Stderr, "RECOVERIES_TEST_NATS_URL is required")
		os.Exit(64)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	connection, err := nats.Connect(natsURL, nats.Name("recoveries-jetstream-proof"))
	if err != nil {
		panic(err)
	}
	defer connection.Close()

	js, err := jetstream.New(connection)
	if err != nil {
		panic(err)
	}
	stream, err := js.CreateOrUpdateStream(ctx, jetstream.StreamConfig{
		Name:       "RECOVERIES_PROOF",
		Subjects:   []string{"fact.verified.v1"},
		Storage:    jetstream.MemoryStorage,
		Duplicates: 2 * time.Minute,
	})
	if err != nil {
		panic(err)
	}

	publisher, err := broker.NewNATS(connection)
	if err != nil {
		panic(err)
	}
	eventID := "00000000-0000-4000-8000-000000001099"
	envelope := []byte(`{"schema_version":"1.0","event_id":"00000000-0000-4000-8000-000000001099"}`)
	if err := publisher.Publish(ctx, "fact.verified.v1", envelope, eventID); err != nil {
		panic(err)
	}
	if err := publisher.Publish(ctx, "fact.verified.v1", envelope, eventID); err != nil {
		panic(err)
	}

	info, err := stream.Info(ctx)
	if err != nil {
		panic(err)
	}
	if info.State.Msgs != 1 {
		panic(fmt.Errorf("JetStream dedupe stored %d messages; expected 1", info.State.Msgs))
	}

	proof := struct {
		EventID        string `json:"event_id"`
		PublishCalls   int    `json:"publish_calls"`
		StoredMessages uint64 `json:"stored_messages"`
		Result         string `json:"result"`
	}{
		EventID:        eventID,
		PublishCalls:   2,
		StoredMessages: info.State.Msgs,
		Result:         "PASS_TRANSPORT_DEDUPE_ONLY",
	}
	encoded, err := json.Marshal(proof)
	if err != nil {
		panic(err)
	}
	fmt.Println(string(encoded))
}
