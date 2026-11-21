# Core API

All business routes are under `/api/v1`, require `Authorization: Bearer <API_KEY>`, accept JSON, and return JSON. [Billing rules](BILLING_RULES.md) define the contract and accounting behavior; [ROADMAP.md](../ROADMAP.md) tracks completion.

## Resources

| Method | Route | Body / result |
| --- | --- | --- |
| POST | `/api/v1/customers` | `{"customer":{"name":"Acme","email":"billing@example.test"}}` |
| GET | `/api/v1/customers` | Paginated customer list in ascending ID order |
| GET | `/api/v1/customers/:id` | Customer detail |
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

## Errors

Errors use `{"error":{"code":"...","message":"..."}}`. Malformed JSON or a missing/wrong-shaped root object returns 400. Invalid fields return 422. Missing referenced resources return 404. Duplicate customer emails return 409 `resource_conflict`; subscription overlap returns 409 `subscription_overlap`; changed payloads under a used key return 409 `idempotency_conflict`; late new usage after issuance returns 409 `usage_period_closed`. Internal database details are not exposed.

Public `/up` and `/ready` health routes and authenticated `/api/v1/status` remain available. Stripe webhooks and collection are not implemented in this milestone.
