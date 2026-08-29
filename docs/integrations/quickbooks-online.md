# QuickBooks Online connector boundary

The Step-18 adapter is read-only. It uses the QuickBooks Online Accounting API generic query endpoint at `POST /v3/company/{realm_id}/query` with an OAuth 2.0 bearer token, an explicit `minorversion`, and a text query body. The endpoint shape and OAuth requirement are reflected in Intuit's developer collection: https://www.postman.com/intuit-developer/intuit-developer-quickbooks-online-accounting-api/request/4884662-168fc705-0c39-48fc-bf4e-337d197f91c4.

Only `Invoice` and `Payment` queries are accepted. The adapter emits observations containing the external ID, transaction date, decimal amount string, explicit currency, optional customer ID, and payment-to-invoice links. Amounts are never parsed through binary floating point. Pagination is explicit (`STARTPOSITION`/`MAXRESULTS`) and bounded to 1,000 pages. Non-success response bodies are discarded so accounting payloads and credentials do not escape in errors.

The adapter does not create, update, or delete QBO entities, persist local payment rows, allocate cash, or accrue fees. Those actions remain deterministic local boundaries in later steps. A token source is injected so credentials can be supplied through the Secret Broker/Vault path without placing secrets in connector code.
