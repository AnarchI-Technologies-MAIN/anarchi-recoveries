# Procore connector boundary

The Step-17 adapter is intentionally read-only. It calls Procore REST v1.0 `GET /rest/v1.0/companies/{company_id}/projects` with an OAuth bearer token and the required `Procore-Company-Id` header, then maps only the stable project identity fields (`id`, `name`, and `project_number`) into the canonical Recoveries shape. The endpoint and header requirement are from Procore's first-party API reference: https://developers.procore.com/reference/rest/company-projects?version=1.0.

The adapter does not write to Procore, persist local business state, or treat vendor fields as authority. It uses explicit `page`/`per_page` pagination, rejects malformed or missing project identities, redacts non-success response bodies, and bounds pagination to 1,000 pages. A token source is injected so connector credentials remain outside the adapter and can later be supplied through the Secret Broker/Vault path.

The returned `Project` values are observations only:

```text
ExternalID    = Procore project id as a decimal string
Name          = required non-empty project name
ProjectNumber = optional project number
SourceSystem  = procore
SourceVersion = rest.v1.0
```

Mapping an observed project to an internal tenant/project remains a separate, explicitly authorized application step.
