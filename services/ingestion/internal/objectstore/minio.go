package objectstore

import (
	"bytes"
	"context"
	"fmt"

	"anarchi.tech/recoveries/ingestion/internal/ingest"
	"github.com/minio/minio-go/v7"
)

type MinIO struct {
	client *minio.Client
}

func NewMinIO(client *minio.Client) (*MinIO, error) {
	if client == nil {
		return nil, fmt.Errorf("minio client is required")
	}
	return &MinIO{client: client}, nil
}

func (m *MinIO) PutIfAbsent(ctx context.Context, bucket, key string, body []byte, metadata ingest.ObjectMetadata) error {
	opts := minio.PutObjectOptions{
		UserMetadata: map[string]string{
			"sha256":            metadata.SHA256,
			"original-filename": metadata.Filename,
		},
		ContentType:    "application/octet-stream",
		SendContentMd5: true,
	}
	opts.SetMatchETagExcept("*")
	if _, err := m.client.PutObject(ctx, bucket, key, bytes.NewReader(body), int64(len(body)), opts); err != nil {
		return fmt.Errorf("conditional put: %w", err)
	}
	return nil
}

func (m *MinIO) Head(ctx context.Context, bucket, key string) (ingest.ObjectMetadata, error) {
	info, err := m.client.StatObject(ctx, bucket, key, minio.StatObjectOptions{})
	if err != nil {
		return ingest.ObjectMetadata{}, fmt.Errorf("stat object: %w", err)
	}
	return ingest.ObjectMetadata{
		SHA256:   info.Metadata.Get("X-Amz-Meta-Sha256"),
		Filename: info.Metadata.Get("X-Amz-Meta-Original-Filename"),
		Size:     info.Size,
	}, nil
}
