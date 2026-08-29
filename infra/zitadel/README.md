# Self-hosted identity boundary

Frozen provider: ZITADEL OIDC. The local Compose file is a disposable, loopback-only
discovery and integration proof. It is not a production deployment manifest.

The image is pinned to ZITADEL v4.16.2 and its multi-platform OCI manifest digest.
Configuration follows the official Compose and external-URL requirements current at
the Step 9 transition:

- https://zitadel.com/docs/self-hosting/deploy/compose
- https://zitadel.com/docs/self-hosting/manage/custom-domain
- https://zitadel.com/docs/self-hosting/manage/requirements

Production activation additionally requires the frozen ingress, Secret Broker/Vault,
backup, observability, governance, and release gates. No credential belongs in this
directory or in Git.
