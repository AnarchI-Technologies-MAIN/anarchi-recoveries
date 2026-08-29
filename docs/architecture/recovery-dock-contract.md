# Recovery Dock contract

Status: Step 36 framework-neutral companion view

`@anarchi/ui` exposes a read-only `RecoveryDock` view-model matching the frozen
desktop signature feature:

```text
ANARCHI / RECOVERIES
Open recoverable total
Urgent count
Urgent items
[ Open Rescue ]
```

The total and every urgent item amount are decimal-string `MoneyLine` values
with provenance. Urgent IDs are unique, and the count is derived from the item
list rather than supplied independently. `Open Rescue` is a navigation target,
not an external side effect. The contract does not open a window, fetch data,
or authorize a recovery action; a desktop adapter must do those things through
the server-authoritative application boundary.
