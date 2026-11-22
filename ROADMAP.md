# Ledgerly Project Roadmap

Created: 2026-11-21
Status: Milestones 0–4 implemented and locally accepted for the test-mode portfolio API. Publishing uses two logical commits; hosted quality and Compose gates validate the exact release revision before promotion to main.
Project name: Ledgerly. The current workspace directory is named `Ledgerdy`.

## How to use this file

This file is the source of truth for project scope, progress, decisions, and evidence.

- Read it before starting project work and reference the relevant milestone in updates.
- Complete work in dependency order. The four weeks below are planning estimates, not completion claims.
- Check a task only after its acceptance checks pass. Record the commands, results, and evidence paths in the work log.
- Update this file when scope or implementation decisions change, and identify the next unfinished task before stopping.
- Keep actual measurements separate from targets. Never put an unmeasured target on a resume.

## Goal and scope

Build a Rails API that ingests metered usage, generates invoices, and reconciles Stripe test-mode payments while preventing duplicate billing effects during retries, concurrent execution, and out-of-order webhook delivery.

Initial scope: one currency per invoice, integer quantities, fixed per-unit metered prices, UTC billing periods, and Stripe test mode. Taxes, discounts, prorations, foreign exchange, production payment rollout, and a custom frontend are outside the initial release.

Use the foundation stack: Rails 8.1 API mode (updated from the proposed Rails 7; see decision log), PostgreSQL, Sidekiq, Redis, Stripe, RSpec, SimpleCov, Sorbet, RuboCop, Docker Compose, and GitHub Actions. Confirm and pin compatible, supported dependency versions during setup; record any change to the proposed Rails major version before implementation.

## Billing and reliability rules

1. PostgreSQL is authoritative for usage, invoices, payment state, and ledger balances. Redis is for queues and disposable read caches.
2. Store money in integer minor units with an explicit currency. Snapshot prices on invoice lines so later plan changes cannot change historical invoices.
3. Use half-open billing periods: `period_start <= occurred_at < period_end`. Define the late-usage policy before implementing invoice generation.
4. Enforce idempotency with database uniqueness and transactions. Application-level existence checks alone are insufficient under concurrency.
5. The same usage key and payload returns the original result. Reusing that key with a different payload returns a conflict.
6. Generating the same subscription-period invoice repeatedly or concurrently produces one invoice, one set of line items, and one issuance journal.
7. Each journal has multiple debit/credit rows whose totals match within one currency. Do not assert that there is exactly one ledger row per Stripe event.
8. Deduplicate both webhook delivery by Stripe event ID and financial effects by the underlying payment/refund identity. Different events may describe the same payment.
9. Use Stripe-managed invoice collection for the initial integration: a local invoice maps to one Stripe invoice. Do not also create a separate charge or PaymentIntent for that invoice. Subscription synchronization must not create a second recurring billing path.
10. Persist stable idempotency keys and remote identifiers for outgoing Stripe operations. Recover from timeouts by reconciling remote state before creating a new operation.
11. Persist webhook receipt before acknowledging it. A durable dispatch record and recovery process must cover failure between database commit and Sidekiq enqueue.
12. Retryable failures must leave work recoverable. A crash after applying an effect must not cause that effect to be applied twice.

## Architecture

```mermaid
flowchart LR
    Client[API client] --> API[Rails API]
    Stripe[Stripe test mode] --> Hook[Signed webhook endpoint]
    API --> PG[(PostgreSQL)]
    Hook --> PG
    PG --> Dispatch[Durable job dispatcher]
    Dispatch --> Redis[(Redis / Sidekiq)]
    Redis --> Worker[Background workers]
    Worker --> PG
    Worker --> Stripe
    API --> Cache[(Redis read cache)]
```

Keep Stripe network calls outside long-running database transactions. Persist intent first, perform the remote operation with a stable idempotency key, and then persist the result. Recovery jobs reconcile interrupted transitions.

## Data model checklist

| Entity | Required data and constraints |
| --- | --- |
| `customers` | API identity, billing identity, unique nullable Stripe customer ID |
| `plans` | Metric, integer unit price, currency, billing cadence |
| `subscriptions` | Customer/plan references, lifecycle, billing boundaries, Stripe mapping when applicable |
| `usage_events` | Customer/subscription, metric, positive integer quantity, occurrence time, idempotency key, request fingerprint; unique key within its documented scope |
| `invoices` | Subscription, billing period, currency, amount, lifecycle, unique Stripe invoice ID; unique subscription and billing period |
| `invoice_line_items` | Invoice, metric, aggregated quantity, snapshotted price, amount, usage allocation reference |
| `ledger_transactions` | Journal type, invoice/payment/refund reference, unique business-effect key |
| `ledger_entries` | Journal, account, debit, credit; invoice/currency via the journal; nonnegative amounts and exactly one positive side per row |
| `stripe_events` (Milestone 2) | Unique Stripe event ID, type, raw payload, processing state, attempts, last error, processing timestamps |
| `outbox_records` (Milestone 2) | Durable dispatch intent, destination job, reference, availability and dispatch state |

Add foreign keys and correctness constraints from the start. Preserve those in the baseline; defer optional performance indexes to the optimization milestone. Journal balance needs transaction-level validation and tests; row-level checks alone cannot enforce a total across multiple entries.

## Milestone 0 — Foundation (start of Week 1)

- [x] Confirm Ruby/Rails/dependency versions and record them in the decision log.
- [x] Scaffold the API application in a dedicated `app/` directory, keeping the existing reference repositories separate.
- [x] Add Docker Compose services for API, PostgreSQL, Redis, and Sidekiq, with health checks and persistent database storage.
- [x] Add `.env.example`, ignored secrets, and documented setup/migration/test commands.
- [x] Configure RSpec, SimpleCov, RuboCop, and Sorbet. Start coverage collection before application code loads.
- [x] Establish API-key authentication, JSON validation/error conventions, pagination limits, and a health endpoint. Stripe webhooks use signature verification instead of API-key authentication.
- [x] Create an initial GitHub Actions workflow for RSpec and RuboCop; expand it in Week 4.

Acceptance status: passed from a clean GitHub checkout. All services booted healthy, setup exited 0, the real worker smoke passed, and `bin/ci` passed (44 examples; clean lint and initial typing). The first hosted GitHub Actions run passed. See [verification evidence](docs/verification/milestone-0/README.md).

Acceptance: a clean checkout can boot the services, create/migrate the database, serve health checks, and run a smoke test using documented commands. No secrets are committed.

## Milestone 1 — Core API and accounting (Week 1)

- [x] Implement migrations, models, relationships, and required database constraints.
- [x] Implement customer and plan creation/read endpoints plus subscription creation, retrieval, and supported lifecycle transitions.
- [x] Document usage idempotency scope, subscription overlap rules, rounding, billing boundaries, and late-usage handling. See [billing rules](docs/BILLING_RULES.md).
- [x] Implement `POST /api/v1/usage_events` with request fingerprints and database-backed idempotency.
- [x] Implement invoice generation for one subscription-period in a database transaction, including line items, usage allocation, and a balanced issuance journal.
- [x] Implement paginated customer invoice lists, invoice detail, and ledger-derived balance endpoints.
- [x] Add request/service tests for validation, authentication, boundary timestamps, price snapshots, duplicate requests, payload conflicts, rollback, and concurrent invoice generation.

Acceptance status: passed from a clean GitHub checkout and fresh schema load. All 138 specs, lint, initial typing, autoload checks and hosted CI passed. Live four-request HTTP duplicate tests produced one event/invoice and balanced entries. See [Milestone 1 evidence](docs/verification/milestone-1/README.md).

Acceptance: repeated and concurrent usage requests have one stored result; repeated and concurrent invoice generation produces one invoice; no usage is billed in two invoices; failed generation leaves no partial invoice or ledger state; every journal balances.

## Milestone 2 — Stripe integration and recovery (Week 2)

- [x] Confirm current Stripe SDK/API contracts against official documentation and pin the API version used by fixtures and tests. SDK 21.1.0 / API 2026-11-18.endive.
- [x] Implement the local-invoice-to-Stripe-invoice workflow with stable outgoing idempotency keys and persisted operation state.
- [x] Implement webhook signature verification against the exact request bytes, with invalid signatures rejected before storage or dispatch.
- [x] Store verified events durably under a unique Stripe event ID and write dispatch intent in the same database transaction.
- [x] Implement the outbox dispatcher and a recovery sweep for undispatched events and interrupted processing.
- [x] Process `invoice.paid`, `invoice.payment_failed`, and `charge.refunded` with database locking, business-effect uniqueness, and transactional ledger/state updates.
- [x] Support multiple partial refunds using individual refund identities; prevent cumulative refunded amounts from exceeding the recognized payment.
- [x] Handle unknown event types, missing mappings, duplicate events, and stale/out-of-order state transitions explicitly. Reconcile against Stripe where local information is insufficient.
- [x] Configure bounded exponential retry backoff with jitter, Sidekiq dead-job handling, failure inspection, and safe manual replay.
- [x] Test concurrent delivery, distinct event IDs for the same payment, duplicate refund notifications, and crashes before/after commit or enqueue.

Acceptance status: passed locally from a fresh schema-loaded database: 195 specs, 117 clean linted files, scoped typing/autoload passing, real Redis interruption recovery, and a real Stripe sandbox payment/refund demonstration with 12 reverse-order duplicate replays. See [Milestone 2 evidence](docs/verification/milestone-2/README.md) and [Stripe operations guide](docs/STRIPE_RELIABILITY.md). No commits, pushes, or hosted CI runs were performed.

Acceptance: replaying events two or three times in shuffled order produces the same financial state as one successful processing pass. There is one journal per logical financial effect, balanced entries, and no repeated Stripe collection. Temporary failures recover, and exhausted jobs remain inspectable and replayable.

## Milestone 3 — Baseline, load, and optimization (Week 3)

- [x] Write a deterministic, rerunnable test-data generator for at least 50,000 invoices with realistic customer distribution, line items, usage, payments, and ledger records.
- [x] Verify fixture counts and accounting invariants before benchmarking. Run benchmarks only against an isolated test environment.
- [x] Write repeatable load scenarios for signed webhook ingestion and a heavy endpoint such as the customer invoice list.
- [x] Record the baseline source identity, machine/container resources, worker concurrency, dataset seed, endpoint parameters, warm-up, duration, arrival rate, and cache state. Base Git revision plus local SHA-256 manifests are used while commits are suspended.
- [x] Run and save the baseline before adding performance optimizations. Keep required integrity indexes enabled.
- [x] Capture endpoint p50/p95/p99, request failures, incoming event rate, successfully processed unique event rate, queue latency, backlog, query counts, and database query plans. Completed two read passes, one steady webhook probe and one overloaded trial; limitations are recorded.
- [x] Add query-informed composite/partial indexes, filter recovery work in SQL, check list/detail/balance paths with Bullet (no N+1 found), and preserve bounded pagination.
- [x] Add bounded Redis caching for balance/invoice-header reads with transaction-versioned invalidation. Cache outage fallback, committed payment while Redis is down, rollback, stale SQL snapshots and late fills all pass.
- [x] Re-run the identical workloads on matching business fingerprints and resource caps. Save cache-off results, two warm repeats and separate single cold application-cache misses; PG/OS caches were not cleared.
- [x] Run duplicate/out-of-order replay across all 50,000 invoices: 180,000 signed service-level deliveries / 60,000 distinct events, exactly 50,000 payments and 5,000 refunds, balanced journals and zero receivables per currency. Corrected observer snapshots bypass SQL query caching; fresh audits and repeated replay pass.
- [x] Save the comparison, reproducible commands, raw outputs, preserved failures, base Git revision and image/source SHA-256 manifests, with cold/warm and throughput limitations.

Acceptance status: complete locally. The [immutable baseline](docs/benchmarks/2026-11-21-baseline-v1/README.md) and [optimized comparison](docs/benchmarks/2026-11-21-optimized-v1/README.md) retain both read repeats, cache-off/cold-miss/warm results, full webhook queue/drain evidence, the failed SDK-descriptor candidate, real Redis outage verification and all-invoice correctness replay. Final fresh-schema checks: 221 passing specs, 142 linted files clean, scoped typing/autoload passed, 96.99% line coverage. High-rate processing fully drained but had 15 client capacity drops and remained below 5,000 unique events/minute; that target is not claimed. The isolated mixed fixture was restored and benchmark services stopped. The refreshed development stack/worker are healthy, with financial counts unchanged. No commits or pushes.

Acceptance: another person can reproduce the measurements from the saved instructions. Throughput counts completed unique effects as well as accepted deliveries; backlog growth and error rates are disclosed. Performance changes preserve all correctness checks.

## Milestone 4 — Quality and portfolio release (Week 4)

- [x] Enforce greater than 90% application line coverage: final 1,256/1,288 (97.51%); branches 229/269 (85.13%). Coverage floors are 90% line / 80% branch.
- [x] Add useful Sorbet contracts to core models, billing services and webhook processors. 45 checked files / 147 signature declarations; typed result records and snapshot shapes; positive/negative probes and generated Rails interfaces. Dynamic boundaries remain documented.
- [x] Finish GitHub Actions with PostgreSQL/Redis, the full quality command, coverage artifacts with commit identity, RBI drift/autoload/type-probe gates and a separate clean Compose HTTP/worker job. Exact hosted results attach to each pushed revision.
- [x] Finish README/API/setup, architecture/schema, billing, Stripe configuration/replay, typing and release documentation.
- [x] Publish the measured baseline/comparison and raw evidence in commit `5976771`; add a hash-verified 157-file baseline source archive and optimized source revision for reconstruction. Preserve original evidence/manifests.
- [x] Document operational checks and add `ledgerly:status` plus a read-only financial audit. Corruption/allocation detection tests and real CLI checks pass.
- [x] Run final clean-source/fresh-database acceptance: 224 specs, 149 Ruby files lint clean, Sorbet/probes/RBI/autoload passed; fresh Compose HTTP/worker/audit passed; real Stripe sandbox decline→70¢ capture→20¢/50¢ refunds plus 12 reverse-order replays passed. Repeat 180,000 signed deliveries across all 50,000 invoices on the typed runtime; zero replay/invariant failures.
- [x] Write resume bullets using only saved measurements and explicit source/test scope. Do not claim 5,000 processed events/minute or an unmeasured latency result for Milestone 4.

Acceptance status: local release checks passed. [Milestone 4 report](docs/verification/milestone-4/README.md) records exact source/image hashes, clean setup, raw checks, measured coverage, type scope, sandbox and replay. The separate acceptance volumes were removed; the mixed 50k fixture was restored and benchmark services stopped. The ordinary development stack is healthy with retained test-mode data. Publishing uses a release-branch gate for the second commit and fast-forwards that same revision to main after hosted checks pass; [workflow results](https://github.com/amovingman/Ledgerly/actions/workflows/ci.yml) and its SHA-tagged coverage artifacts identify the final hosted result without an extra documentation-only commit.

Acceptance: clean setup succeeds, quality/CI gates pass, the demo is repeatable, and every numerical claim links to a completed measurement. The portfolio release is not a production payment rollout or a complete static proof of every dynamic path.

## Evidence and measurement register

Targets/examples come from the proposal. Only the actual-result column records achieved measurements, with the scope stated explicitly.

| Claim | Target / example | Required proof | Actual result |
| --- | --- | --- | --- |
| Event throughput | 5,000+ events/minute | Signed load test; accepted deliveries and completed unique events/minute; duration, errors, backlog and queue latency | At 100 offered deliveries/s: 5,985 submitted, zero HTTP failures, 15 client drops; 5,387 unique events and exactly 4,790 payment effects completed over 64.86 s including offering/drain (4,983.24 unique/min). End-of-offering rate: 4,871.06 unique/min. Steady probe: all 270 events / 240 effects completed. The 5,000/min target remains unproven. [Comparison](docs/benchmarks/2026-11-21-optimized-v1/README.md) |
| Duplicate billing prevention | Zero duplicates in the tested scenarios | Concurrent, repeated and shuffled event replay; unique logical payment/refund journals; outgoing collection count; balanced ledger assertions | All 50,000 invoices participated in 180,000 shuffled signed service-level deliveries / 60,000 events. Exactly 50,000 payments, 5,000 refunds and 105,000 balanced journals / 210,000 rows; all receipts processed, eight checks clean and zero receivables per currency. In-process provider; not an external-charge throughput test. The final typed runtime repeats those totals and a fresh real Stripe sandbox capture/refund/replay passes. Scope remains the tested scenarios. [Replay](docs/benchmarks/2026-11-21-optimized-v1/full-replay.json) |
| Dataset size | At least 50,000 invoices | Seed command, deterministic seed, counts, and integrity checks | 50,000 invoices, 150,000 usage events, 40,000 initial payments, 5,000 refunds and 190,000 initial ledger rows. Rebuilds match 11 table fingerprints; all accounting checks passed. [Counts](docs/benchmarks/2026-11-21-baseline-v1/dataset-counts.json) |
| Heavy-endpoint latency | Example: p95 480 ms → 90 ms | Comparable baseline/optimized runs with identical fixtures and resources; request failures; cold/warm cache disclosure | At 40 arrivals/s, baseline p95s in two passes: page 1 30.81/30.36 ms, page 10 756.52/53.32 ms, balance 40.26/95.32 ms. Warm optimized repeats: 15.89/15.93, 11.12/10.46 and 10.98/12.07 ms respectively; zero failures/drops. Cache-off and separate single cold application-cache observations retained; PG/OS caches not flushed. Shared-VM baseline variability disclosed. [Comparison](docs/benchmarks/2026-11-21-optimized-v1/README.md) |
| RSpec coverage | Greater than 90%; stretch 94% | Full-suite command, SimpleCov configuration and report showing actual line coverage | Milestone 4: 1,256/1,288 application lines (97.51%); branches 229/269 (85.13%); 224 specs, zero failures. Enforced floors: 90% line / 80% branch. Scripts, specs and lib/ helpers/tasks are outside application-only coverage. [Checks](docs/verification/milestone-4/checks-release.log) |

Suggested evidence layout, to create as measurements are produced:

```text
docs/benchmarks/<run-id>/
  environment.md
  commands.md
  dataset-counts.json
  baseline.json
  optimized.json
  replay-results.txt
  query-plans.txt
  comparison.md
```

Store the commit and fixture identity with each run. Keep secrets and customer data out of evidence. A test with no duplicate charges supports a claim about those tested failure scenarios; it does not prove that duplicates are impossible under every condition.

## Definition of done for each milestone

- Relevant tasks and acceptance checks pass.
- Required automated checks pass, and important recovery/concurrency cases have evidence.
- Setup/API/operational documentation matches the implementation.
- This roadmap reflects completed work, open decisions, actual measurements, and the next task.

## Decision log

| Date | Decision | Rationale / follow-up |
| --- | --- | --- |
| 2026-11-21 | Use this roadmap as the project reference | Update it as implementation and evidence evolve. |
| 2026-11-21 | Keep the application in `app/` | The workspace currently contains reference repositories rather than an application. |
| 2026-11-21 | Use Stripe-managed invoice collection for the initial release | Map each local invoice to one remote invoice and avoid competing collection paths. Verify contracts during Milestone 2. |
| 2026-11-21 | Add journal headers and durable dispatch records | Provide business-effect uniqueness and recovery across database/queue boundaries. |
| 2026-11-21 | Move the foundation from Rails 7 to Rails 8.1 | Rails 7.2 reached its final release; use a security-supported release for new development. Sources: https://rubyonrails.org/2026/9/24/Rails-Version-7-2-4-has-been-released and https://rubyonrails.org/maintenance. |
| 2026-11-21 | Commit logical batches near 1,000 changed lines to `amovingman/Ledgerly` | User requested frequent commits; exclude bundled reference repositories and generated runtime files. |
| 2026-11-21 | Pin Ruby 3.4.13, Rails 8.1.4.1, Bundler 4.1.0 and all direct gems | RubyGems versions checked; `app/Gemfile.lock` includes macOS arm64 and Linux arm64/x86_64. Local tools: PostgreSQL 17.12, Redis 8.10.3, Docker 29.10.0, Compose 5.8.0, Colima 0.10.3. Container Redis is pinned independently in Compose. |
| 2026-11-21 | Scope the initial Sorbet check to strict pagination value objects | Keep the type check useful and passing now; model/service signatures expand in Milestone 4. |
| 2026-11-21 | Isolate test database settings from development | Tests use `TEST_DB_DATABASE` / `TEST_DATABASE_URL`, ignore inherited generic database overrides, and refuse names without a test suffix; CI/specs reject production invocation. |
| 2026-11-21 | Suspend all commits and pushes at user request | Keep Milestone 2 local; identify the accepted source with a SHA-256 manifest and base revision instead of creating a commit or running hosted CI. |
| 2026-11-21 | Pin Stripe SDK 21.1.0 / API 2026-11-18.endive; use invoice-managed collection only | Confirmed current SDK contracts and actual sandbox payment/refund flow. Support one full card payment per invoice and multiple partial refunds; unsupported snapshots enter review. |
| 2026-11-21 | Bound ambiguous outgoing creation to 23 hours | Reconcile remote operation metadata before retrying; refuse new creates beyond the conservative window. Manual replay preserves payloads, keys, and first-attempt timestamps. |
| 2026-11-21 | Run independent durable recovery every 15 seconds | Recover pending outbox work and dispatches/attempts stale for five minutes. Eight processing attempts with jittered backoff, dead/review inspection, and safe manual replay. |
| 2026-11-21 | Keep initial Sorbet scope while excluding incomplete Stripe vendor RBIs | `bin/typecheck` preserves other gem RBIs and strict pagination checks. Complete model/service/SDK typing remains Milestone 4. |
| 2026-11-21 | Complete the dataset/baseline phase before optimizing | User requested measurements first. Use separate volumes and fixture credentials, eager-loaded benchmark Rails, NullStore, a read-only provider stub, and fixed workloads. Preserve both read repeats and overload failures; do not present accepted delivery rates as processing throughput. |
| 2026-11-21 | Use transaction-versioned billing caches and SQL-selected recovery work | Commit customer read versions with financial writes; bounded Redis failures fall back to PostgreSQL. Select unfinished/stale outbox targets before row locking; keep the inner recheck and original integrity constraints. |
| 2026-11-21 | Reuse one Stripe SDK client per worker thread | Load exposed transport pool accumulation at the unchanged 1,024-descriptor limit. Reuse validates credentials/options and keeps the slot bounded; accepted high-rate run finished with 24 descriptors. |
| 2026-11-21 | Run benchmark accounting snapshots without Active Record SQL caching | An initial replay report reused observer counts from before worker commits. Preserve it and its fresh audit; regression and full repeated replay prove the corrected evidence. Only the observer helper/test changed after timed runs; both image/source identities are retained. |

Milestone 1 billing decisions are defined in [docs/BILLING_RULES.md](docs/BILLING_RULES.md): UTC calendar months, late usage accepted until issuance, non-overlapping customer/metric subscriptions, contract price snapshots, and issuance debits to receivables/credits to usage revenue. Milestone 2 payment/refund contracts and recovery are defined in [docs/STRIPE_RELIABILITY.md](docs/STRIPE_RELIABILITY.md); credit adjustments remain outside initial scope.

## Work log

| Date | Work completed | Validation / evidence | Next task |
| --- | --- | --- | --- |
| 2026-11-21 | Created the roadmap and persistent project-reference instructions | Inspected workspace; no Rails application found. No application tests or benchmarks run. | Milestone 0: confirm versions and scaffold the Rails API. |
| 2026-11-21 | Installed development tools; scaffolded Rails 8.1 API in `app/`; pinned dependencies | `ruby --version`, `bundle --version`, `bundle exec rails --version`, and `bundle check` passed. Colima VM started. Application acceptance checks still pending. | Add and verify auth, errors, health, tests, Compose, and CI. |
| 2026-11-21 | Implemented API auth, JSON errors, pagination, health endpoints, test database guards, and quality tooling | Container `bin/ci`: 44 examples, 0 failures; RuboCop: 41 files, no offenses; scoped Sorbet: no errors. Foundation-only SimpleCov line coverage: 102/110 (92.72%). Native Rails autoload and database isolation/production guard checks passed. | Complete live worker/HTTP and clean-checkout acceptance; commit infrastructure and documentation. |
| 2026-11-21 | Added Compose, pinned development images, setup docs, environment example, and GitHub Actions | Full stack healthy; real `bin/smoke` passed; live HTTP checks returned 200 health/authenticated, 401 unauthenticated, 404 unknown route, 400 malformed JSON. First commits pushed: `f8e7d19`, `d443842`. | Verify the committed infrastructure from a clean checkout and inspect hosted CI. |
| 2026-11-21 | Completed Milestone 0 acceptance from clean GitHub source at `70aea13`; saved outputs and setup evidence | [Verification report](docs/verification/milestone-0/README.md): healthy full stack, real worker execution, 44 specs passing, 41 Ruby files lint clean, initial Sorbet passing; [hosted CI passed](https://github.com/amovingman/Ledgerly/actions/runs/44962119095). Workflow checkout runtime updated to the verified Node 24 release after a deprecation annotation. | Milestone 1: implement migrations/models and core API, beginning with billing rules and database constraints. |
| 2026-11-21 | Started Milestone 1 and documented billing, lifecycle, late-usage, locking, and account-mapping rules | Implementation and checks in progress; no new acceptance claims yet. | Verify migrations, model constraints and schema round-trip, then build the API and billing services. |
| 2026-11-21 | Implemented eight core models, database constraints, schema dump, contract price snapshots and subscription lifecycle services | Migration and fresh `db:schema:load` verified in isolated test databases; full batch check: 70 specs passing, 52 linted files clean, Sorbet passing. Invoice/usage services and endpoints are still pending. | Build resource endpoints and customer-scoped idempotent usage ingestion. |
| 2026-11-21 | Implemented authenticated customer/plan/subscription endpoints, cancellation and idempotent usage API | Full container check: 113 passing specs, 63 linted files clean, scoped Sorbet passing. Tests cover normalized timestamps, cross-customer isolation, key conflicts/replays, late usage, payload types and boundaries. Model batch `9318d52` passed hosted CI. | Implement atomic invoice generation, invoice/balance reads, and real concurrency/rollback checks. |
| 2026-11-21 | Added atomic invoice issuance, one-time allocation, balanced immutable journals, invoice reads and per-currency receivable balances | Full container check: 138 passing specs; 73 linted files clean; scoped Sorbet passing. Real four-thread duplicates produce one event/invoice/journal; ingestion/issuance race, rollback after allocation, month boundaries and integer overflow are verified. | Verify the committed schema from scratch, live API workflow, and hosted CI before marking Milestone 1 complete. |
| 2026-11-21 | Completed Milestone 1 acceptance against clean GitHub source `2a1aa1d` and a fresh schema-loaded test database | [Evidence](docs/verification/milestone-1/README.md): 138 specs passing, 73 linted files clean, scoped typing/autoload passing; [hosted CI green](https://github.com/amovingman/Ledgerly/actions/runs/44964611834). Real HTTP concurrency verified one event and one invoice, balanced postings, immutable replay and late-usage rejection. | Milestone 2: verify Stripe contracts/version and implement durable collection/webhook processing with recovery. |
| 2026-11-21 | Started Milestone 2; user requested continued work without GitHub commits | Existing Milestones 0–1 remain verified. New work will stay local and uncommitted; no hosted CI runs will be triggered. | Pin verified Stripe contracts, then implement durable collection, webhook processing and recovery tests. |
| 2026-11-21 | Implemented local Stripe collection intents, persisted operation keys, signed receipts, outbox/recovery, payment/refund reconciliation, retries and manual replay | Interim run: 186 specs passed against PostgreSQL/Redis, including SDK HTTP contracts, concurrency and real Redis dead-job handling. Final acceptance and sandbox verification followed below; no commits or pushes made. | Finish local checks and durability smoke test; run a real sandbox demo if test environment details become available. |
| 2026-11-21 | Completed Milestone 2 locally, including real sandbox verification and operational documentation | [Evidence](docs/verification/milestone-2/README.md): fresh-schema acceptance 195 specs, 96.64% line / 84.46% branch coverage, 117 linted files clean, scoped typing and autoload passing; real Redis outage recovered; sandbox failed→paid→two refunds, 12 reverse-order duplicate replays, one captured charge per tested invoice, balanced journals. Main stack healthy. No commits/pushes. | Milestone 3: design deterministic 50,000-invoice fixtures and record a baseline before optimization. |
| 2026-11-21 | Claimed the verified Ledgerly Stripe sandbox after the user created their account | Dashboard opened `Ledgerly sandbox` under the original sandbox account. Existing test credentials retrieved the same paid test invoice successfully; [claim verification](docs/verification/milestone-2/sandbox-claim.json). Application source unchanged; no new payments, commits, or pushes. | Milestone 3: isolated dataset and baseline before optimization. |
| 2026-11-21 | Started Milestone 3 dataset and baseline at user request | Inspected current query paths and Docker resources (2 vCPU / 4 GiB shared VM). No optional indexes, caching, or application query changes applied. | Build guarded isolated fixtures, validate accounting/determinism, then capture read and signed-webhook baselines. |
| 2026-11-21 | Built the first isolated 50,000-invoice fixture | 1,000 customers, 1,460 subscriptions, 150,000 usage events, 40,000 payments, 5,000 refunds, 95,000 balanced journals / 190,000 ledger rows. Eight accounting checks found zero violations; sampled SQL/provider contracts and usage fingerprints match. Expanded suite: 201 specs passing. | Confirm rerun determinism and capture baseline under fixed load; no optimizations applied. |
| 2026-11-21 | Verified fixture determinism and concurrent replay preflight before timed baseline | Two rebuilds match all 11 table fingerprints; resetting after preflight reproduces the same fixture. A 100-invoice sample received 900 shuffled deliveries / 300 distinct events, producing exactly 20 previously absent payments with zero accounting violations. Final suite: 202 specs, 131 clean linted files, scoped typing/autoload passing. | Complete fixed read and signed-webhook baselines and preserve raw evidence; full 50,000-invoice replay and optimization remain pending. |
| 2026-11-21 | Completed Milestone 3 dataset and unoptimized baseline phase | [Report](docs/benchmarks/2026-11-21-baseline-v1/README.md): 50,000 invoices, matching rebuild fingerprints, 202 passing specs, 131 clean linted files, scoped typing/autoload passing; two read passes saved. Steady webhook probe: 300 deliveries, 270 unique events, 240 new payments, no backlog/errors/drops. High-rate overload and tail variability retained honestly. Benchmark services stopped with data volumes retained; main API healthy. No commits/pushes. | Review baseline, then profile/optimize and run a matched comparison; all-50,000-invoice replay remains pending. |
| 2026-11-21 | Started the Milestone 3 optimization phase at user request | Preserved the original measured image; profile the historical outbox sweep, provider calls, and query plans before choosing changes. Baseline artifacts remain unchanged. | Apply targeted improvements, prove cache correctness/recovery safety, and rerun matching workloads and full-dataset replay. |
| 2026-11-21 | Profiled and optimized stale recovery selection, added targeted indexes and transaction-versioned Redis reads | Isolated sweep: 200,042 SQL statements / 21.75 s before, 3 statements / 0.093 s after. Fresh-schema suite: 216 specs passing, 141 linted files clean, scoped typing/autoload passing. Cache tests cover late fills, rollback, Redis failures and payment/refund state changes; Bullet positive control works and endpoint checks found no N+1. | Finish matched uncached/warm/cold-first measurements, live cache-outage verification, and full 50k replay before claiming milestone acceptance. |
| 2026-11-21 | Matched read passes improved, but high-rate webhook replay exposed SDK transport pool accumulation | Preserved `.tooling/m3-after` candidate evidence: 902 processed events before the worker reached 1,021 open descriptors under a 1,024 soft limit. Added per-thread SDK client reuse with configuration validation/rotation; no resource limits raised. Candidate results are not final acceptance. | Rebuild, run regression checks, repeat the matched benchmarks, then complete Redis outage and full 50k correctness replay. |
| 2026-11-21 | Fixed per-job SDK transport accumulation with per-thread client reuse; retained the failed candidate overload run | Fresh schema-loaded acceptance checks: 220 specs, zero failures; 141 Ruby files lint clean; scoped Sorbet/autoload passed. SimpleCov 1,032/1,064 lines (96.99%), 229/269 branches (85.13%). Credential validation, rotation and thread separation have regression coverage. | Complete the repeated matched benchmark batch and all-invoice replay on image `a1b8378ce208`; do not raise resource/file limits. |
| 2026-11-21 | Completed accepted-image matched measurements and real Redis outage verification | Cache-off p95s 16.20/18.15/17.23 ms (first/deep/balance); warm repeats 15.89/15.93, 11.12/10.46, 10.98/12.07 ms. Steady: 270 processed events / 240 payments, completion p95 87.89 ms. High: 5,387 accepted/processed, 4,790 payments, 15 client drops, zero HTTP failures; fully drained in 64.86 s including offering, 4,983 unique/min including drain. Worker used 24 descriptors at unchanged 1,024 soft limit. Redis-down payment and stale-cache restart check passed. Raw final evidence under `.tooling/m3-final`; comparison is being assembled. | Finish the 180,000-delivery all-invoice replay and publish local evidence/docs; 5,000/min target remains unproven. |
| 2026-11-21 | Completed first 180,000-delivery replay and caught stale observer counts in its report | Fresh independent uncached audit confirms 50,000 payments, 5,000 refunds, 60,000 processed receipts, 105,000 journals / 210,000 rows, zero invariant violations and zero receivables by currency. Corrected benchmark-only `Verify` to bypass SQL query cache; added real committed-write regression. Final checks: 221 specs, 142 clean linted files, same 96.99% line coverage, typing/autoload passing. Timed image retained unchanged; only observer helper/test differ in separately tagged verification image. | Repeat the full replay with corrected observer, then restore fixture, verify development health and save final evidence. |
| 2026-11-21 | Completed Milestone 3 optimization, repeated full correctness replay and final acceptance | [Report](docs/benchmarks/2026-11-21-optimized-v1/README.md): sweep 200,042 statements / 21.75 s to 3 / 0.075 s; matched reads and webhooks retained; 180,000 signed deliveries across all 50,000 invoices with fresh final accounting, zero replay failures and no duplicate financial effects. 221 specs / 142 clean linted files; scoped typing/autoload passed; line coverage 96.99%. Redis-down payment and stale-key restart passed. Original 50k fixture restored and benchmark services stopped; refreshed development API and real worker smoke passed with unchanged financial counts. HEAD remains `23e0e76`; no commits/pushes. | Milestone 4: expand Sorbet coverage, finish CI/operational/release docs and acceptance; publishing remains suspended. |
| 2026-11-22 | Started Milestone 4; user re-enabled GitHub publishing in two commits | Prior accepted executable manifest still matches all files; pre-publish scan found no private values in 371 public files (about 10.5 MB). First commit captures verified Milestones 2–3; second completes Milestone 4 typing/CI/docs and acceptance. | Expand useful Sorbet contracts, enforce coverage/typing in CI, complete release/operations docs and final clean acceptance before the second push. |
| 2026-11-22 | Pushed verified Milestones 2–3 as commit `5976771`; expanded Sorbet model/service/webhook contracts | [First hosted CI passed](https://github.com/amovingman/Ledgerly/actions/runs/45051940771). Generated real Rails column/association/relation RBIs. Static checks pass across core models and billing/Stripe services; initial runtime run caught a permitted-parameters/hash boundary mismatch, corrected by explicit controller normalization. Full runtime acceptance is being repeated. | Finish coverage/RBI/type-probe CI gates, release/operations docs and final sandbox/clean-checkout acceptance, then commit/push Milestone 4. |
| 2026-11-22 | Completed Milestone 4 implementation and local release acceptance | [Final report](docs/verification/milestone-4/README.md): 224 passing specs, 149 clean linted files, 97.51% line / 85.13% branch coverage; 147 signatures across 45 checked files, negative/positive type probes, real-schema RBI drift and autoload passing. Credential-free fresh Compose HTTP/worker/ledger checks passed. Real sandbox: one 70¢ capture, two refunds, 12 reverse replays, balanced four journals/eight rows. Final typed all-invoice replay: 180,000 deliveries / 60,000 receipts, exactly 50k payments/5k refunds, zero failures, 210k balanced rows; fixture restored and benchmark services stopped. Baseline source archive matches 157 original hashes. | Verify the second commit on a release branch, fast-forward the same SHA to main, confirm hosted jobs and remote identity, and retain exactly two new main commits. |

## Next action

The four-milestone test-mode API implementation and local acceptance are complete. Final publication uses exactly two main-history commits: `5976771` for verified Milestones 2–3, and the Milestone 4 release commit. Verify that exact revision's hosted quality/Compose jobs before promotion to main; [CI status and source-tagged artifacts](https://github.com/amovingman/Ledgerly/actions/workflows/ci.yml) record the result. No production deployment or additional release tag is part of this work. Future feature scope needs a new roadmap decision; keep all benchmark and static-typing limitations explicit.
