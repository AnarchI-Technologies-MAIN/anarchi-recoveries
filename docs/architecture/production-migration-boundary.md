# Production migration and restore boundary

Status: Steps 39–40 readiness baseline; production is not authorized

`docs/runbooks/production-migration-readiness.v1.json` maps the frozen Stage A
WSL2 spine to the ten logical workloads in the dedicated early-production
stack. It also pins the early-production objectives: PostgreSQL RPO of at most
15 minutes, Core Recoveries RTO of at most 4 hours, nightly independent full
backups, continuous/incremental database protection, at least one encrypted
off-stack backup, and scheduled recorded restore testing.

The manifest is `NOT_AUTHORIZED` with every preflight check false. The validator
proves the map and objectives without contacting or mutating a live service.
Authorization is impossible until authority approval, rollback approval,
backup/restore proof, Secret Broker/Vault readiness, observability readiness,
and dedicated-stack reachability are all independently receipted.
