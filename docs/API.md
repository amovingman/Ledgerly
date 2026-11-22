# API reference

All business routes are under `/api/v1`, require `Authorization: Bearer <API_KEY>`, accept JSON, and return JSON. [Billing rules](BILLING_RULES.md) define the contract and accounting behavior; [ROADMAP.md](../ROADMAP.md) tracks completion.

## Resources

| Method | Route | Body / result |
| --- | --- | --- |
| POST | `/api/v1/customers` | `{"customer":{"name":"Acme","email":"billing@example.test"}}` |
| GET | `/api/v1/customers` | Paginated customer list in ascending ID order |
| GET | `/api/v1/customers/:id` | Customer detail including server-managed `stripe_customer_id` |
| POST | `/api/v1/plans` | `{"plan":{"name":"API calls","metric":"api_calls","unit_amount":7,"currency":"USD"}}` |
| GET | `/api/v1/plans` | Paginated plan list in ascending ID order |
| GET | `/api/v1/plans/:id` | Plan detail |
| POST | `/api/v1/subscriptions` | `{"subscription":{"customer_id":1,"plan_id":1,"starts_at":"2026-01-01T00:00:00Z"}}`; omit `starts_at` to start now |
| GET | `/api/v1/subscriptions/:id` | Subscription detail including snapshotted metric, price and currency |
| POST | `/api/v1/subscriptions/:id/cancel` | No body; cancellation is safe to repeat |
| POST | `/api/v1/usage_events` | Usage body below; requires `Idempotency-Key` header |

Resource creation returns `201 {"data":{...}}`; reads/cancellation return `200 {"data":{...}}`. IDs are positive integers (decimal strings are accepted for references). Quantities and unit prices must be JSON integers; floats, booleans and numeric strings are rejected. Timestamps are UTC-normalized with six fractional digits. Client-supplied lifecycle, pricing snapshots, remote Stripe IDs, totals and ledger attributes are not writable.

Lists accept `page` (default 1) and `per_page` (default 25, maximum 100) and return `{"data":[...],"meta":{"page":1,"per_page":25,"total":1}}`. Ordering is deterministic. No delete or arbitrary update endpoints are exposed.

```json
{
  "usage_event": {
    "customer_id": 1,
    "subscription_id": 1,
    "metric": "api_calls",
    "quantity": 10,
    "occurred_at": "2026-01-15T12:00:00.000001Z"
  }
}
```

Send a key such as `Idempotency-Key: customer-1-request-123`. A first ingestion returns 201 and `Idempotency-Replayed: false`. Replaying equivalent usage returns 200, the same immutable `data` body, and `Idempotency-Replayed: true`. Fingerprints are internal and allocations are excluded from the response.

## Invoices and balances

| Method | Route | Body / result |
| --- | --- | --- |
| POST | `/api/v1/subscriptions/:subscription_id/invoices` | `{"invoice":{"period_start":"2026-01-01T00:00:00Z"}}` |
| GET | `/api/v1/customers/:customer_id/invoices` | Paginated invoice headers ordered by `created_at DESC, id DESC` |
| GET | `/api/v1/invoices/:id` | Invoice header, snapshotted `line_items`, and balanced `journals` with entries |
| GET | `/api/v1/customers/:customer_id/balance` | `{"data":{"customer_id":1,"balances":[{"currency":"USD","amount":70}]}}` |
| POST | `/api/v1/invoices/:invoice_id/collection` | No body; `202` with persisted collection status; repeats return the same intent |
| GET | `/api/v1/invoices/:invoice_id/collection` | Collection status, attempt count, safe last-error code, remote invoice ID |
| GET | `/api/v1/stripe_events/:stripe_id` | Receipt processing metadata; excludes raw payload |

Invoice creation is synchronous and transactional. It returns 201 for first issuance and 200 for a repeat subscription/month, with `Idempotency-Replayed` identifying a replay. It never invokes Stripe or collects money. The server derives the month end, unit price, usage quantity, currency and amount; client overrides are ignored. Completed calendar months with no usage return 422 `no_usage`, open months return 422 `period_not_closed`, and non-month-boundary starts return 422 `invalid_period`.

Invoice detail includes ledger accounts/debits/credits for auditability. Header amounts and usage/pricing snapshots are immutable through the API. Balances sum receivable journal rows, not invoice statuses, and return one amount per currency; an empty ledger returns `balances: []`.

A first issuance closes only that subscription's month. New late usage is rejected afterward, while existing usage-key and invoice-generation retries remain safe. A failed posting rolls back the invoice, line, allocation, and journal together.

Collection is asynchronous and requires test-mode Stripe configuration. A `202` or collection `succeeded` means the collection intent/finalized remote invoice exists, not that payment is recognized. Invoice headers include server-managed `stripe_invoice_id`. Signed reconciliation changes the local status to `payment_failed`, `paid`, or fully `refunded`; partial refunds leave it `paid` and add refund journals. Repeating collection never starts a second intent. Totals below the configured currency minimum or above the application cap return `422 unsupported_collection_amount`. See [Stripe contracts and recovery](STRIPE_RELIABILITY.md).

## Stripe webhook

`POST /webhooks/stripe` requires a valid `Stripe-Signature` rather than an application API key. Send the exact signed bytes using the pinned `2026-11-18.endive` snapshot version. The test-mode receipt and outbox commit before `200 {"received":true,"duplicate":false}`. Repeated delivery returns `duplicate:true`; asynchronous processing can still be pending when acknowledgment succeeds. Redis unavailability does not discard a stored receipt.

Invalid signatures, live/Connect events, and unexpected API versions return 400 before storage. Requests larger than 1 MiB return 413. Conflicting payloads for a stored event ID return 409. A missing webhook signing secret returns 503. Unknown event types are accepted then marked `ignored`; supported types are `invoice.paid`, `invoice.payment_failed`, and `charge.refunded`. Inspect event processing through the authenticated metadata endpoint.

## Errors

Errors use `{"error":{"code":"...","message":"..."}}`. Malformed JSON or a missing/wrong-shaped root object returns 400. Invalid fields return 422. Missing referenced resources return 404. Duplicate customer emails return 409 `resource_conflict`; subscription overlap returns 409 `subscription_overlap`; changed payloads under a used key return 409 `idempotency_conflict`; late new usage after issuance returns 409 `usage_period_closed`. Internal database details are not exposed.

Public `/up` and `/ready` health routes and authenticated `/api/v1/status` remain available. Missing Stripe credentials affect collection/webhook capabilities; core local billing remains available.
