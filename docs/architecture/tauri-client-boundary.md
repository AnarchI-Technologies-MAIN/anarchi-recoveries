# Windows Tauri client boundary

Status: Step 32 boundary baseline; shell packaging is not yet claimed

`apps/client/src-tauri` currently contains the native-boundary contract that a
Tauri 2 shell must honor before a binary is packaged:

- the installed client is a networked client of the server, never a second
  recovery authority;
- the only cache kinds admitted offline are recent opportunity summaries,
  previously opened evidence, deadlines, project metadata, and draft comments;
- an offline approval can only enter `QUEUED` state;
- reconnect must revalidate the opportunity, payload hash, policy, deadline, and
  authority before the server may execute anything;
- an offline client cannot perform an external submission, independent pricing,
  independent entitlement evaluation, or authoritative recovery evaluation;
- the status model keeps online/offline mode, last sync, core version, and
  evaluation version visible.

The crate deliberately has no Tauri dependency yet. This makes the authority
and offline rules testable without pretending that an `.exe`, installer,
signing path, secure OS storage, or live server adapter already exists. Steps
33–40 add those deployment and operational layers only after this boundary is
held by the actual client.
