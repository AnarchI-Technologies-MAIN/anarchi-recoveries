# Native notification privacy boundary

Status: Step 35 notification contract; provider wiring is not enabled

The client shell exposes three target identities—Windows desktop, iOS, and
Android—and two explicit privacy settings:

- `Private` is the default lock-screen-safe mode. It emits only the generic
  `AnarchI Recoveries update available` body, even when confidential detail is
  available to the application.
- `Detailed` is an explicit opt-in mode. It requires a nonempty detail value
  and marks the payload as not lock-screen safe.

The contract does not register push providers, send notifications, or place
customer evidence in a transport. This keeps native delivery and device-token
authority for the later client integration work while making the privacy rule
testable now.
