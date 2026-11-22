# Milestone 2 verification

Completed locally on **2026-11-21 America/Toronto** (sandbox report timestamps are UTC on November 22). See [ROADMAP.md](../../../ROADMAP.md#milestone-2--stripe-integration-and-recovery-week-2) and [Stripe setup and recovery](../../STRIPE_RELIABILITY.md).

This source is **uncommitted**. Git base: `23e0e76c90429375bcc6331d12ec1a171a642517`. [source-manifest.json](source-manifest.json) identifies the local source files by SHA-256. No commit, push, or hosted CI run was performed for this milestone. The manifest records the later claim-documentation amendment separately; application source hashes did not change after acceptance. Earlier Milestone 0–1 GitHub evidence describes those earlier revisions only.

## Automated acceptance

[checks.txt](checks.txt) is the final container output. A new PostgreSQL database was created and loaded directly from the local `db/schema.rb` before the complete check:

```sh
docker compose build api
docker compose up --no-build -d --wait
docker compose run --name ledgerly-m2-schema-checks --no-deps \
  -e RAILS_ENV=test -e TEST_DB_DATABASE=ledgerly_m2_schema_test \
  -e REDIS_URL=redis://redis:6379/1 api sh -c \
  'bin/rails db:create db:schema:load && bin/ci && bin/rails zeitwerk:check'
```

Use a new database name ending in `_test` for a new schema-load acceptance run; schema loading replaces that selected database's schema. The saved run created `ledgerly_m2_schema_test` from scratch. The log's initial orphan-container warning refers to stopped earlier check containers; those have since been removed.

| Check | Actual result |
| --- | --- |
| RSpec | 195 examples, 0 failures; randomized seed 33014 |
| SimpleCov lines | 952/985, **96.64%** |
| SimpleCov branches | 212/251, **84.46%** |
| RuboCop | 117 Ruby files, no offenses |
| Sorbet | `bin/typecheck`: no errors; initial pagination/value-object scope |
| Zeitwerk | Eager loading passed |
| Main Compose stack | API, PostgreSQL, Redis, Sidekiq, recovery healthy; setup exited 0 |
| Real worker smoke | `PASS: Rails -> Redis -> Sidekiq -> PostgreSQL -> Redis` |

[coverage.json](coverage.json), [services.json](services.json), and [worker-smoke.txt](worker-smoke.txt) contain the corresponding evidence. SimpleCov starts before Rails, covers `app/**/*.rb`, and excludes specs. The HTML artifact is generated at ignored `app/coverage/index.html`. Model/service Sorbet signatures remain Milestone 4 work; the wrapper excludes the Stripe gem's incomplete vendor RBI graph while retaining other gem RBIs.

The suite includes all previous core API/accounting checks plus:

- Exact-byte signatures, stale/invalid signatures, size/version/mode/context rejection, immutable raw receipts, concurrent duplicate delivery, conflicting payloads, durable receipt/outbox rollback.
- Persisted outgoing operation payloads/keys; timeout recovery after customer, invoice, item creation and finalization; remote reconciliation; no second create after the 23-hour uncertainty limit; manual replay preserving that limit.
- Actual pinned SDK HTTP contracts using WebMock, including headers, attached invoice-item encoding, refund pagination, and network-failure classification. RSpec makes no external Stripe calls.
- Concurrent distinct events for one charge, refund-before-payment/failure ordering, multiple partial refunds, duplicate refunds, pending-refund settlement retry, cumulative refund caps, and transaction rollback before event completion.
- Queue commit/enqueue gaps, stale dispatch recovery, worker attempt budgets, safe manual replay, and real `Sidekiq::JobRetry`/Redis dead-set handling rather than only invoking an exhausted callback directly.

## Real Redis interruption

[redis-interruption.json](redis-interruption.json) reports a separate live HTTP/worker check in disposable Compose project `ledgerly-m2-verify` on port 3001. The main application was not interrupted.

The [script](redis-interruption.py) signed an unknown event, observed the real worker mark it ignored, replayed it successfully, and rejected a bad signature with 400. It then stopped that project's Redis, delivered another signed receipt, and observed HTTP **200** with database status `received`. After restarting Redis, the independent recovery loop and real worker completed it as `ignored`, with one processing attempt. No provider API call was needed for this unknown event.

To repeat, create an ignored `.tooling/m2-verify.env` with a dedicated API key and `STRIPE_WEBHOOK_SECRET=whsec_localverification` (a local fixture signing value), leave `STRIPE_SECRET_KEY` blank, and start only the disposable project:

```sh
PORT=3001 docker compose -p ledgerly-m2-verify \
  --env-file .tooling/m2-verify.env up --no-build -d --wait
python3 docs/verification/milestone-2/redis-interruption.py
PORT=3001 docker compose -p ledgerly-m2-verify \
  --env-file .tooling/m2-verify.env down --volumes
```

The script assumes the documented Docker environment is on PATH. The verification stack/volumes were removed after the successful run. Main application volumes and sandbox invoice mappings were preserved.

## Real Stripe sandbox

The user authorized a temporary claimable Stripe sandbox, created with official CLI **1.55.14**, account `acct_1UeObYCbPgJp5f4v`. The CLI listener reported API `2026-11-18.endive` and forwarded actual Stripe events to the main local API on port 3000. The original unclaimed deadline was **2026-11-29**. The user subsequently created a Stripe account, and the sandbox was claimed on **2026-11-21**. The dashboard shows `Ledgerly sandbox` under the original account ID, and the application's existing test credentials still retrieve the same paid invoice. See [sandbox-claim.json](sandbox-claim.json). Claim URL, CLI config, and keys remain in ignored private local files.

With a sandbox configured and API/worker/recovery/listener running, the saved [sandbox-smoke.rb](sandbox-smoke.rb) can be executed with a fresh synthetic fixture:

```sh
docker compose exec -T -e STRIPE_SMOKE_RUN_ID=acceptance-20261121 \
  api bin/rails runner - < docs/verification/milestone-2/sandbox-smoke.rb
```

Use a new run ID for an independent scenario. The script uses only test PaymentMethods and a completed UTC month. It exercises real business HTTP routes for customer, plan, subscription, usage, invoice, and collection; actual Sidekiq workers perform outgoing collection and reconciliation. The verification script explicitly pays the same finalized invoice to accelerate the test; the application itself relies on Stripe-managed collection.

[sandbox-results.json](sandbox-results.json) is the final passing fresh-fixture run (`local_invoice_id: 2`). [sandbox-delivery.txt](sandbox-delivery.txt) contains the four real provider delivery/200 acknowledgment pairs without the listener signing secret.

| Observation, scoped to that invoice/customer | Actual result |
| --- | --- |
| Issued invoice | USD 70 minor units (70¢) |
| Collection | Succeeded, one worker attempt |
| Declined test attempt | One failed charge; actual `invoice.payment_failed` processed |
| Successful retry on the same invoice | **One** successful captured charge, 70 minor units; actual `invoice.paid` processed |
| Partial refunds | Two succeeded refunds, 20 + 50 minor units; both actual `charge.refunded` events processed |
| Replayed deliveries | Four stored real payloads, three extra passes in reverse order: **12 duplicate acknowledgments** |
| Final local financial identities | One payment, two refunds |
| Final journals | Four journals / eight rows; debits 210 = credits 210 minor units |
| Final invoice / receivable | `refunded` / USD 0 |

Each replay was freshly signed by the local verification script using the listener secret; these were simulated duplicate HTTP deliveries of authentic stored payloads, not additional Stripe-origin deliveries. Out-of-order *first processing* and concurrent distinct events are covered separately by the deterministic tests. Two synthetic invoices were exercised during development; the passing report's counts are explicitly scoped to its one invoice/customer, not the whole sandbox account.

## Limits

These checks demonstrate no duplicate financial effects in the tested scenarios. They do not prove that duplicates are impossible under every failure or administrative action. Stripe-managed collection, one full card payment per invoice, and individual succeeded refunds define this milestone's payment contract. Unsupported credits/shared/partial invoice payments require review. Long pending refunds may exhaust retries and need inspection/replay; later refund reversals and disputes need additional accounting workflows.

There was no 50,000-invoice dataset, load test, 5,000-events/minute measurement, or latency comparison in this milestone. Those remain [Milestone 3](../../../ROADMAP.md#milestone-3--baseline-load-and-optimization-week-3).
