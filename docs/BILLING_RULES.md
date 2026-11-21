# Core billing rules

These rules implement [Milestone 1](../ROADMAP.md#milestone-1--core-api-and-accounting-week-1). Stripe collection and reconciliation remain in Milestone 2.

## Contracts and periods

- Amounts are integer currency minor units, quantities are positive integers, and multiplication is exact. No rounding is required for this initial pricing model.
- Supported currencies: USD, CAD, EUR, GBP. Unit prices and individual usage quantities are limited to 1–1,000,000,000; invoice totals must fit a signed PostgreSQL bigint.
- Plans are metered, monthly, and have a positive unit price. Subscriptions snapshot the plan metric, price and currency when created. Later plan edits cannot reprice an existing contract or invoice.
- Billing periods are full UTC calendar months: `[period_start, period_end)`. A subscription may start or stop within a month; only usage in its active interval is chargeable, with no fixed fee or proration.
- An invoice can be issued only after the month ends and only when there is unbilled usage. No-usage periods return `422 no_usage` and create nothing.
- For a customer and metric, subscription active intervals cannot overlap, including cancelled historical intervals. Different metrics can coexist. A PostgreSQL exclusion constraint enforces this rule under concurrency.
- Lifecycle: `active` → `cancelled`, effective immediately. Repeating cancellation returns the same state. Cancelling before a future start creates an empty interval. Resuming a cancelled contract is unsupported; create a new subscription instead.

## Usage and retries

- `Idempotency-Key` is required for usage requests: 1–128 ASCII letters, digits, `.`, `_`, `:`, or `-`. Keys are unique within a customer across subscriptions.
- Fingerprints use canonical subscription ID, metric, integer quantity, and occurrence time normalized to UTC with microsecond precision. JSON key order and equivalent timezone offsets do not change the fingerprint.
- A successful first request returns 201. A replay returns 200 with the same immutable event body and `Idempotency-Replayed: true`. A valid different payload under that key returns `409 idempotency_conflict`.
- Occurrence timestamps require RFC3339 with an explicit timezone and at most six fractional digits. Future usage, metric mismatches, and events outside `[starts_at, ends_at)` are rejected.
- Late usage is accepted until that subscription's calendar-month invoice is issued. Issuance closes the month: later new events return `409 usage_period_closed`. There is no automatic carry-forward or retroactive invoice mutation.
- Replaying an accepted event still returns its original result after cancellation or invoice issuance. Usage allocation is internal and is excluded from the immutable API response.

## Atomic issuance and accounting

- Ingestion, subscription creation/cancellation, and invoice issuance lock the customer row inside a PostgreSQL transaction. This serializes billing decisions for that customer and prevents late-usage/issuance races. It is a deliberate correctness-first tradeoff to measure before optimization.
- Database unique indexes backstop usage keys, subscription-period invoices, line-item metrics and journal effect keys. Composite foreign keys prevent usage/invoices from referencing another customer's subscription.
- Issuance creates the invoice, price/quantity snapshot, usage allocation and complete journal in one transaction. Repeating or concurrently generating the same subscription-period returns the existing invoice. A failure rolls back every effect.
- One usage event has at most one line-item allocation. Issuance only allocates previously unbilled events within its subscription and half-open month.
- Issuance journal: debit `accounts_receivable`, credit `usage_revenue`, each for the invoice amount. Journal currency must match the invoice, with at least two rows and equal debit/credit totals. Each row has exactly one positive side.
- Reserved for Milestone 2: payments debit `stripe_clearing` and credit `accounts_receivable`; refunds debit `sales_returns` and credit `stripe_clearing`. Credit adjustments and payment/refund reconciliation are not implemented in Milestone 1.
- Journal balance and aggregate invoice/allocation consistency are validated by the posting service transaction and tests. Row checks alone do not enforce sums across rows; administrative SQL bypassing the service is outside that application guarantee. Ledger rows and line snapshots are read-only through models and the API.
- Customer balances come from `accounts_receivable` debits minus credits grouped by journal currency, using PostgreSQL rather than a cache or invoice status. Currencies are never added together.

## Database schema portability

The pinned Rails 8.1 PostgreSQL adapter supports dumping the composite foreign keys and exclusion constraint into `db/schema.rb`. Verify schema loading in the acceptance checks; migrations and the schema must preserve the same integrity constraints.
