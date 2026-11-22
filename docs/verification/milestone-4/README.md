# Milestone 4 release acceptance

Recorded **2026-11-22 America/Toronto**. [ROADMAP.md](../../../ROADMAP.md#milestone-4--quality-and-portfolio-release-week-4) is the project reference. [Release instructions](../../RELEASE.md), [typing scope](../../TYPING.md), [operations](../../OPERATIONS.md), [machine-readable summary](summary.json).

This records local acceptance before the second release commit. GitHub Actions checks the exact pushed revision and uploads coverage with `GITHUB_SHA`/run identity. [Hosted workflow results](https://github.com/amovingman/Ledgerly/actions/workflows/ci.yml) are the source for that final status; this report does not invent a hosted run result before publication. The release branch gates the same commit that is subsequently fast-forwarded to `main`.

## Source and clean setup

The accepted source starts at published commit `5976771de93b4dc938bb5f610a7999f259fb2ff8` plus the files in [the release source manifest](release-source-manifest.json). [Image identity](release-image-id.json) and [offline verification](image-source-verification.json) check **303 shipped application files**. No network, database, environment or credential lookup was used for that image comparison.

A snapshot containing only publishable files was copied to an ignored working directory; `.env`, host `.bundle`, private `.tooling` and Stripe CLI state were absent. Docker built from that snapshot. A separate `ledgerly-release-acceptance` Compose project booted with **fresh PostgreSQL/Redis volumes**, fixture credentials and loopback port 3004. The main sandbox database was separate. [Service state](clean-services.ndjson).

Fresh database creation/preparation/migration commands succeeded and [all four migrations are up](migration-chain.log). The suite also ran against a separate fresh schema-loaded test database. [Initial database commands](migrations.log), [complete checks](checks-release.log). The disposable acceptance volumes were [removed afterward](clean-shutdown.log).

One later correction fixes the typecheck wrapper's explanatory comment about the intentionally excluded Stripe exported RBI graph. [The delta](comment-only-delta.json) proves the Ruby syntax tree is identical. Financial runtime code is unchanged from the accepted image; hosted CI checks the exact published source. Documentation/evidence was completed after local execution.

## Quality gates

| Check | Actual local result |
| --- | --- |
| RSpec | **224 examples, 0 failures**, seed 30596 |
| Application line coverage | **1,256 / 1,288 (97.51%)**, enforced floor 90% |
| Application branch coverage | **229 / 269 (85.13%)**, enforced floor 80% |
| RuboCop | **149 Ruby files**, no offenses |
| Sorbet | No errors across configured application definitions and typed core bodies |
| Type probes | Valid client accepted; wrong result record, wrong webhook record and integer/string-method misuse rejected |
| RBI synchronization | Gem versions and actual schema/DSL output match |
| Rails autoload | Passed |

Coverage includes `app/**/*.rb`; benchmark helpers, Rake tasks, scripts and specs are outside that application-only percentage. CI uploads complete coverage artifacts. Runtime signatures were enabled during RSpec and the sandbox run.

[Typing inventory](typing-scope.json): 45 of 70 application Ruby files have `typed: true`/`strict` headers, with **147 signature declarations**, 106 generated gem RBIs and 17 DSL RBIs. These are inventory counts, not a percentage of fully proven expressions. Core model attributes/associations, service input/output contracts and generic result records are typed; framework/SDK/JSON boundaries remain gradual. Stripe's unresolved exported V2 RBI graph is not globally suppressed: the pinned API is reflected and the gateway has explicit contracts. [Details](../../TYPING.md).

`bin/ci` now runs coverage-gated specs, lint, types, positive/negative probes, RBI drift and autoload checks. GitHub Actions has a separate clean Compose HTTP/worker job. Checkout/setup/artifact actions are pinned; upload-artifact v7.0.2 uses Node 24. Coverage artifacts include exact commit/run identity and are retained for 14 days.

## HTTP, background execution and operations

[Real-worker smoke](worker-smoke.log) passed through Rails → Redis → Sidekiq → PostgreSQL → Redis. [HTTP smoke](core-smoke.log) created a unique synthetic customer/plan/subscription, replayed identical usage, rejected a conflicting payload, replayed invoice generation, and read the same 70-minor-unit USD balance twice with caching enabled. No outgoing Stripe operation was requested in this clean flow.

[General ledger audit](ledger-audit.log) reports **zero violations in all eight checks**. [Queue/durable status](operations-status.log) shows Redis available, no pending/dead/retry work and empty queues at the observation. The new audit uses an uncached read-only repeatable-read snapshot and normal billing data, not benchmark counts. Tests demonstrate detection of an administratively corrupted journal and an unallocated usage event even when journals still balance.

## Real Stripe test-mode acceptance

The ordinary development stack was refreshed to the accepted image and new local listener secret. The listener reported pinned API `2026-11-18.endive`. Keys and signing secret remained ignored. The original sandbox acceptance runner was executed with fresh label **`m4-20261122`** against the same claimed sandbox; it used real local HTTP, real Sidekiq and the actual Stripe SDK/API. [Sandbox report](sandbox-results.json), [main worker](main-worker-smoke.log), [main ledger audit](main-ledger-audit.log).

| Scenario | Result |
| --- | --- |
| Collection | One finalized invoice, collection succeeded on attempt 1 |
| Decline | Local `payment_failed` observed |
| Payment | One successful **70¢ USD simulated test capture**, local `paid` |
| Refunds | 20¢ then 50¢, local `refunded` |
| Reverse-order duplicate deliveries | **12** acknowledged as duplicates |
| Logical effects | One local payment and two local refunds |
| Accounting | Four balanced journals / eight rows; **210 debit = 210 credit** |
| Receivables | USD 0 |

This is test-mode money; no live payment was made. The report includes only synthetic test identifiers and accounting results, not credentials or raw webhook bodies. The temporary listener was stopped after acceptance. Restart/configure a listener as documented before expecting new forwarded sandbox events. The ordinary stack remains healthy with the final implementation and retained test data.

## All-invoice regression and historical performance

[Full replay](full-replay.json), [raw progress/output](full-replay.log): **180,000 signed, globally shuffled/repeated deliveries**, **60,000 unique processed events**, across **all 50,000 invoices**, with four concurrent service workers and an in-process canonical provider. Result: **zero failures**, exactly **50,000 payments**, **5,000 refunds**, **105,000 journals / 210,000 balanced rows**, eight invariant checks clean and zero receivables separately per currency. Payment-origin counts confirm refund-first and stale-failure-first processing occurred. This tests the final typed financial runtime; it is not an HTTP/Sidekiq/live Stripe throughput measurement.

The [mixed fixture was restored](fixture-restored.json), matching all **11 original business table fingerprints**. The added cache-version counter remains excluded as documented in Milestone 3. [Benchmark services were stopped](benchmark-shutdown.log) with their isolated volumes retained.

Historical [Milestone 3 performance](../../benchmarks/2026-11-21-optimized-v1/README.md) remains unchanged, including both before/warm repeats, cache-off results, cold application-cache singles, the descriptor-exhaustion candidate and 15 final high-rate client drops. Milestone 4 does not claim new matched latency after signatures. The 5,000-processed-events/minute target remains unproven. [Source snapshots](../../benchmarks/source-snapshots/README.md) now make the actual baseline application and optimized revision available for reconstruction without an unpublished intermediate commit.

## Publication and limits

The first requested commit `5976771` is published; [its hosted CI passed](https://github.com/amovingman/Ledgerly/actions/runs/45051940771). The second contains Milestone 4 and this acceptance record. Verify that exact commit's hosted quality and Compose jobs before promoting it to `main`; no extra documentation-only commit or production deployment is required. [Artifact manifest](artifact-manifest.json) pins this local report and evidence. Public log copies trim trailing Compose progress whitespace; original local logs remain unchanged, and no measurement/accounting values were rewritten.

These checks support correctness for the tested identities, concurrency, crash/retry and ordering cases. They do not prove every possible duplicate-charge failure is impossible. This release excludes tax/FX, disputes, fees/payout settlement, general split payments, production deployment and full static proof of all dynamic paths. [Resume wording](../../RESUME.md) keeps claims within the measured evidence.
