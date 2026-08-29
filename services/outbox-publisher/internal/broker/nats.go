package broker

import (
	"context"

	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
)

type NATS struct {
	jetstream jetstream.JetStream
}

func NewNATS(connection *nats.Conn) (NATS, error) {
	js, err := jetstream.New(connection)
	if err != nil {
		return NATS{}, err
	}
	return NATS{jetstream: js}, nil
}

func (broker NATS) Publish(
	ctx context.Context,
	subject string,
	envelope []byte,
	eventID string,
) error {
	message := nats.NewMsg(subject)
	message.Data = envelope
	message.Header.Set("Nats-Msg-Id", eventID)
	_, err := broker.jetstream.PublishMsg(ctx, message)
	return err
}
