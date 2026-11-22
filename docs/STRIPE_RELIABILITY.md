# Stripe collection and recovery

This implements [Milestone 2](../ROADMAP.md#milestone-2--stripe-integration-and-recovery-week-2). PostgreSQL stores collection intent, provider operation keys, signed receipts, dispatch intent, and accounting effects. Redis carries jobs; losing a queue message does not erase the database intent.

## Supported contract

The application uses Stripe Ruby SDK **21.1.0**, pinned to API **2026-11-18.endive**. Webhook snapshots must use that version too. Only test credentials (`sk_test_`, `rk_test_`, or claimable-sandbox `rkcs_test_`) are accepted. Live resources and Connect/account-context events are rejected.

One issued local invoice maps to one Stripe invoice. Collection creates/reuses a customer, creates a draft invoice excluding unrelated pending items, attaches the local lines, verifies the total, and finalizes with automatic collection enabled. Repeating the collection request returns the existing intent. The application never creates a separate charge, PaymentIntent, or recurring Stripe subscription for it. Local subscriptions govern usage contracts; they are not synchronized to a second recurring payment path.

Collection requires an issuance journal and a total of at least USD/CAD/EUR 50 or GBP 30 minor units. The conservative application maximum is 99,999,999 minor units. Local issuance can still represent amounts outside this collection range. Taxes, discounts, credits, out-of-band payments, split/partial invoice payments, shared PaymentIntents, and Connect are outside the initial contract. Such payment snapshots require review rather than a guessed ledger posting. Multiple partial refunds of a recognized full card payment are supported.

The reconciler follows current `InvoicePayment` → `PaymentIntent` → captured `Charge` identities. It verifies customer, currency, test mode, gross invoice/payment amounts, and refund identities against canonical Stripe reads. It paginates all payment/refund lists. It does not rely on removed legacy `invoice.charge` fields or trust a webhook's embedded payment totals.

## Configure a local sandbox

Set these in the ignored root `.env` without putting credentials in source or documentation:

```dotenv
STRIPE_SECRET_KEY=<test secret or restricted sandbox key>
STRIPE_WEBHOOK_SECRET=<whsec signing secret from your listener>
```

The core API works without Stripe configuration. Collection then returns 503; webhook receipt also fails closed if its signing secret is missing. Use a restricted key with the customer, invoice, invoice-item, invoice-payment, PaymentIntent, charge, and refund permissions needed by the documented workflow.

Authenticate the official Stripe CLI to the same sandbox. Start the listener on the host:

```sh
stripe listen --latest --events invoice.paid,invoice.payment_failed,charge.refunded \
  --forward-to http://127.0.0.1:3000/webhooks/stripe
```

Confirm the reported API version is `2026-11-18.endive`, copy its signing secret into `.env`, then recreate services:

```sh
docker compose build api
docker compose up --no-build -d --wait
```

`--latest` follows Stripe's current API; if a future CLI reports another version, configure a version-pinned event destination or update the integration and fixtures together. An unexpected version is rejected before storage. Each listener's secret must match the environment used by the receiving API. Stop the listener when finished; forwarding is a local process, not a deployed webhook destination.

For the temporary sandbox created during verification, private CLI configuration, its claim link, and access notes are under ignored `.tooling/stripe/`. It was claimed on **2026-11-21** after the user created their Stripe account; [open Ledgerly sandbox](https://dashboard.stripe.com/acct_1UeObYCbPgJp5f4v/test/dashboard). The original unclaimed deadline was 2026-11-29. Existing application test credentials still passed a read-only invoice check after claiming. No credential or claim token is included in the evidence directory.

## Request collection and inspect processing

Issue an invoice through the [core API](API.md), then send authenticated `POST /api/v1/invoices/:invoice_id/collection`. A 202 response means the durable collection intent exists. It does not mean payment succeeded. Inspect `GET` at that same route for `status`, `attempts`, `last_error`, and the remote invoice ID.

| Work | States | Terminal states |
| --- | --- | --- |
| Collection | `pending`, `succeeded`, `dead`, `review` | `succeeded`, `dead`, `review` |
| Webhook | `received`, `processed`, `ignored`, `dead`, `review` | `processed`, `ignored`, `dead`, `review` |

Collection `succeeded` means the finalized invoice was handed to Stripe. Only reconciliation recognizes money and updates the local invoice to `paid`. A failed unpaid invoice becomes `payment_failed`. A partial refund leaves it `paid`, with refund journals recording the amount; a complete refund sets `refunded`. A delayed failure notification cannot overwrite a recognized payment/refund.

`GET /api/v1/stripe_events/:stripe_id` exposes processing metadata through API-key authentication. It omits raw payloads. Inspect raw receipts only through trusted database/console access; they can contain billing information.

## Idempotency and transactions

Before any outgoing create, a `stripe_operations` row persists the exact immutable payload and a random stable idempotency key. That key is also written to provider metadata. After a timeout, retry lists the relevant remote objects and reconciles matching metadata before another create. Ambiguous matches require review. If the first attempt is at least 23 hours old and no match can be found, the application refuses another create. Manual replay preserves this timestamp and the key. This deliberately stops before Stripe can prune its idempotency cache after 24 hours. Finalization re-reads the known invoice ID and reuses the original finalization key.

Collection workers take a PostgreSQL advisory lock per customer. Event processors take one per event. Provider network calls occur outside database transactions. Milestone 3 reuses one pinned SDK client per worker thread, with a bounded slot that is replaced when credentials/options change. Creating a fresh client for each job accumulated persistent SDK transport pools and exhausted the 1,024-descriptor soft limit during a saved overload trial; the fix keeps that limit unchanged. Missing credentials are still validated on every gateway initialization. Financial posting locks the customer row in a short transaction and atomically commits the event status, invoice status, payment/refund identity records, and balanced journals. Unique indexes protect both delivery IDs and logical financial-effect IDs.

Signature verification uses exact request bytes with a five-minute tolerance and a 1 MiB payload limit. A new receipt and its outbox row commit together before HTTP 200. The same event ID with equivalent parsed JSON is acknowledged as a duplicate; a changed payload returns 409. Unsupported types are durably marked `ignored` without provider API calls.

Payment journals debit `stripe_clearing` and credit `accounts_receivable`. Refund journals debit `sales_returns` and credit `stripe_clearing`. A payment has one journal per charge, a refund one per refund ID; each journal contains multiple balanced rows. Refund totals cannot exceed the recognized payment, including refunds posted by earlier events. Pending/action-required refunds remain retryable until settled; only succeeded refunds are posted. If settlement outlasts the retry budget, inspect and replay after resolving it.

## Recovery and replay

Compose runs a separate `recovery` service every 15 seconds, with a heartbeat health check. It dispatches pending database outbox records and requeues nonterminal work whose dispatch/last attempt is older than five minutes. Recovery filters nonterminal/stale targets in SQL before loading or locking outbox rows, then rechecks under the row lock. Completed historical receipts no longer generate per-record transactions on every sweep. Duplicate queue jobs are safe. A Redis failure during receipt does not change the successful durable acknowledgment. Queue dispatch itself backs off while Redis is unavailable.

Workers use bounded exponential backoff with jitter, at most eight processing attempts, and Sidekiq's dead set. A permanent/unsupported snapshot enters `review` and is moved to the dead set immediately; exhausted retryable work enters `dead`. Advisory-lock contention reschedules without consuming this processing budget. Error fields contain safe application codes, not provider error bodies.

With native services, start a third terminal with the same exported environment as the API and worker:

```sh
cd app
bin/rails runner script/recovery_loop.rb
```

Inspect recovery/worker logs and run a one-off sweep if needed:

```sh
docker compose logs --tail=100 recovery sidekiq
docker compose exec api bin/rails stripe:recover
docker compose exec api bin/rails runner \
  'puts StripeEvent.where(status: %w[dead review]).group(:last_error).count.inspect'
docker compose exec api bin/rails runner \
  'puts OutboxRecord.where(dispatched_at: nil).count'
```

After resolving the underlying issue, replay only dead/review work:

```sh
docker compose exec api bin/rails 'stripe:replay_event[evt_example]'
docker compose exec api bin/rails 'stripe:replay_collection[123]'
```

Replay resets the local attempt budget and dispatch intent; it does not replace signed payloads, provider operation keys, first-attempt timestamps, or existing financial effects. Retrying an expired ambiguous create requires investigation rather than bypassing the 23-hour guard. Sidekiq dead-set records remain available for diagnosis even after an application replay succeeds.

## Verification and boundaries

[Milestone 2 evidence](verification/milestone-2/README.md) separates deterministic SDK/service/concurrency tests, a real Redis interruption, and the real Stripe sandbox demonstration. The live demo explicitly accelerates payment on the same finalized Stripe invoice using test PaymentMethods; that is a verification action rather than another application payment path.

This milestone is not a production billing rollout or a general guarantee against all possible duplicates. Long asynchronous refund reversals, disputes, credit notes, external dashboard edits, fees/payout settlement, and additional payment methods need their own contracts and journals. Inspect/replay unresolved work instead of deleting evidence or mutating immutable journals. Local throughput, all-invoice replay and latency evidence are recorded with their boundaries in [Milestone 3](../ROADMAP.md#milestone-3--baseline-load-and-optimization-week-3) and the [benchmark reports](BENCHMARKS.md).

Primary contracts checked: [idempotent requests](https://docs.stripe.com/api/idempotent_requests), [webhooks](https://docs.stripe.com/webhooks), [invoice creation](https://docs.stripe.com/api/invoices/create), [finalization](https://docs.stripe.com/api/invoices/finalize), [invoice payments](https://docs.stripe.com/api/invoice-payment), [refunds](https://docs.stripe.com/refunds), [test payments](https://docs.stripe.com/testing), and the installed pinned SDK service signatures.
