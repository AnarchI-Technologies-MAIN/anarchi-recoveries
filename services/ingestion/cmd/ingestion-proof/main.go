package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"anarchi.tech/recoveries/ingestion/internal/evidence"
	"anarchi.tech/recoveries/ingestion/internal/ingest"
	"anarchi.tech/recoveries/ingestion/internal/objectstore"
	"anarchi.tech/recoveries/ingestion/internal/repository"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

const (
	organizationID = "00000000-0000-4000-8000-000000001201"
	projectID      = "00000000-0000-4000-8000-000000001202"
	evidenceID     = "00000000-0000-4000-8000-000000001203"
	eventID        = "00000000-0000-4000-8000-000000001204"
	correlationID  = "00000000-0000-4000-8000-000000001205"
	proofBody      = "AnarchI evidence proof bytes\n"
	proofHash      = "ca2427d7ad120f241ea28edfd313e00a28fe0d45327e63d54fad855c0bc63658"
	bucket         = "recoveries-ingestion-proof"
)

func required(name string) string {
	value := os.Getenv(name)
	if value == "" {
		panic(name + " is required")
	}
	return value
}

func main() {
	ctx := context.Background()
	databaseURL := required("RECOVERIES_TEST_DATABASE_URL")
	accessKey := required("RECOVERIES_OBJECT_STORE_ACCESS_KEY")
	secretKey := required("RECOVERIES_OBJECT_STORE_SECRET_KEY")

	admin, err := pgxpool.New(ctx, databaseURL)
	must(err)
	defer admin.Close()
	_, err = admin.Exec(ctx,
		"INSERT INTO recoveries.organizations (id, legal_name) VALUES ($1, 'Step 12 Adapter Proof')",
		organizationID,
	)
	must(err)
	_, err = admin.Exec(ctx, `
		INSERT INTO recoveries.projects (organization_id, id, project_number, name, timezone, currency)
		VALUES ($1, $2, 'STEP-12-ADAPTER', 'Step 12 Adapter Proof', 'UTC', 'USD')`, organizationID, projectID)
	must(err)
	defer func() {
		_, _ = admin.Exec(ctx, "DELETE FROM recoveries.transactional_outbox WHERE organization_id=$1", organizationID)
		_, _ = admin.Exec(ctx, "DELETE FROM recoveries.evidence WHERE organization_id=$1", organizationID)
		_, _ = admin.Exec(ctx, "DELETE FROM recoveries.projects WHERE organization_id=$1", organizationID)
		_, _ = admin.Exec(ctx, "DELETE FROM recoveries.organizations WHERE id=$1", organizationID)
	}()

	client, err := minio.New("127.0.0.1:59000", &minio.Options{
		Creds: credentials.NewStaticV4(accessKey, secretKey, ""), Secure: false,
	})
	must(err)
	must(client.MakeBucket(ctx, bucket, minio.MakeBucketOptions{}))
	defer func() {
		_ = client.RemoveObject(ctx, bucket, objectKey(), minio.RemoveObjectOptions{})
		_ = client.RemoveBucket(ctx, bucket)
	}()

	runtimeConfig, err := pgxpool.ParseConfig(databaseURL)
	must(err)
	runtimeConfig.AfterConnect = func(ctx context.Context, conn *pgx.Conn) error {
		_, err := conn.Exec(ctx, "SET ROLE recoveries_runtime_role")
		return err
	}
	runtimePool, err := pgxpool.NewWithConfig(ctx, runtimeConfig)
	must(err)
	defer runtimePool.Close()

	objects, err := objectstore.NewMinIO(client)
	must(err)
	repo, err := repository.NewPostgres(runtimePool)
	must(err)
	service, err := ingest.New(objects, repo)
	must(err)
	record, err := service.Ingest(ctx, ingest.Request{
		Identity: evidence.Identity{
			OrganizationID: organizationID, ProjectID: projectID, EvidenceID: evidenceID,
			SHA256: proofHash, Filename: "source.bin",
		},
		Bucket: bucket, SourceSystem: "file-upload", ExternalID: "adapter-proof",
		SourceVersion: "1", SourceObservedAt: "2026-08-29T00:00:00Z",
		MIMEType: "application/octet-stream", SizeBytes: int64(len(proofBody)),
		CorrelationID: correlationID, IdempotencyKey: "step-12-adapter-proof",
		EventID: eventID, OccurredAt: "2026-08-29T00:00:01Z", Body: []byte(proofBody),
	})
	must(err)

	var rows int
	must(admin.QueryRow(ctx, `
		SELECT count(*) FROM recoveries.evidence e
		JOIN recoveries.transactional_outbox o
		  ON o.organization_id=e.organization_id AND o.aggregate_id=e.id
		WHERE e.organization_id=$1 AND e.id=$2 AND o.event_id=$3
	`, organizationID, evidenceID, eventID).Scan(&rows))
	if rows != 1 {
		panic("adapter proof did not persist exactly one evidence/outbox pair")
	}
	output, _ := json.Marshal(map[string]any{
		"result": "PASS_INGESTION_ADAPTER_PROOF", "object_uri": record.ObjectURI,
		"evidence_rows": rows,
	})
	fmt.Println(string(output))
}

func objectKey() string {
	key, err := evidence.ObjectKey(evidence.Identity{
		OrganizationID: organizationID, ProjectID: projectID, EvidenceID: evidenceID,
		SHA256: proofHash, Filename: "source.bin",
	})
	must(err)
	return key
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
