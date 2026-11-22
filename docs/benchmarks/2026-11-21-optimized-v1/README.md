# Milestone 3: measured optimization and correctness

Measured locally on **2026-11-21 America/Toronto** (raw UTC timestamps fall on November 22). [ROADMAP.md](../../../ROADMAP.md#milestone-3--baseline-load-and-optimization-week-3) records milestone acceptance and the next work. The [original baseline](../2026-11-21-baseline-v1/README.md) is immutable; its artifact hashes were verified again. [Reproduction guide](../../BENCHMARKS.md), [cache contract](../../CACHING.md), [machine-readable comparison](comparison.json).

The matched workload measurements and the all-50,000-invoice signed correctness replay are complete. Reads and idle recovery improved in these local measurements. The **5,000 processed events/minute target was not demonstrated**; the high-rate probe built a temporary backlog and had client capacity drops before draining. No commits, pushes or hosted CI runs occurred.

## Source, fixture and resources

Base Git revision remains `23e0e76c90429375bcc6331d12ec1a171a642517`. All new source is local/uncommitted. [Source manifest](source-manifest.json), [image ID](image-id.json), and [offline image verification](image-source-verification.json) pin the measured executable; documentation was completed afterward. A subsequent benchmark-only observer fix and regression test are identified by [the final source manifest](final-source-manifest.json), [verification image ID](verification-image-id.json), [verification image/source check](verification-image-source.json), and [exact source delta](verification-source-delta.json). No billing/controller/cache/recovery/SDK/database runtime code changed after timed measurements. The timed local image is `ledgerly-benchmark:optimized`, distinct from the retained baseline `ledgerly-benchmark:unoptimized-20261121` and the failed candidate `ledgerly-benchmark:candidate-20261121`.

Fixed fixture v1/seed **20261121**: 1,000 customers, 1,460 subscriptions, 50,000 invoices, 150,000 usage events, 40,000 initial payments, 5,000 refunds, 95,000 initial journals and 190,000 rows. All eight accounting checks pass. [Fixture comparisons](fixture-comparability.json) verify all 11 baseline table fingerprints before each independent final pass. Only the new monotonic `customers.read_version` cache counter is excluded from fingerprinting; every original business column remains included. This counter starts at zero after each guarded reset. Full replay intentionally prepares a different correctness starting state, described below.

The same shared ARM64 Docker VM has 2 vCPUs / 4 GiB configured (about 3.81 GiB usable). The ordinary development stack remained running and idle during timed runs. API/worker caps stay 1 CPU/512 MiB each; PostgreSQL 1 CPU/768 MiB; provider 0.5 CPU/128 MiB; recovery 0.5 CPU/256 MiB; Redis 0.5 CPU/128 MiB. API threads and Sidekiq concurrency remain 5; recovery remains enabled. [Environment](environment.json), [resource snapshots](container-resources.json). The worker open-file soft limit remains **1,024**. No increased caps hide overload.

The actual pinned Stripe SDK uses the same read-only local HTTP provider, with the same 2 ms minimum service delay per request. The internal network prevents external Stripe traffic. No real Stripe charges were created, and provider writes are forbidden. This is local application capacity with a fixture provider, not Stripe latency/rate-limit evidence. [Provider counters](provider-stats.json).

## Profile and changes

[Before profile](profile-before.json), [after profile](profile-after.json) and their raw logs instrument SQL statements, CPU, wall time and SDK calls on a fresh mixed fixture. Both diagnostic runners use the same 1-CPU/512-MiB seed-service cap; the continuously running recovery service has its original smaller cap. These are individual diagnostic executions, not latency percentiles.

| Diagnostic | Before | Accepted image |
| --- | ---: | ---: |
| Idle recovery sweep SQL statements | 200,042 | 3 |
| Idle recovery sweep wall time | 21.747 s | 0.075 s |
| Idle recovery sweep CPU | 13.026 s | 0.037 s |
| 20 payment reconciliations SQL statements | 600 | 640 |
| 20 payment reconciliations wall time | 1.233 s | 0.954 s |

The original sweep opened per-record transactions and loaded targets across completed historical receipts every cycle. The new sweep selects unfinished/stale targets in SQL, then preserves the locked recheck before dispatch. Partial indexes support unfinished events/collections and pending outbox dispatch. The payment diagnostic adds 40 transactional customer-version writes across 20 reconciliations; this deliberate correctness cost is retained.

Balance and invoice-header reads use bounded, 30-second/64-KiB JSON caches for invoice pages 1–10. A customer version advances in the **same PostgreSQL transaction** as invoice/journal changes; committed versions select new keys. Old fills cannot poison the latest version. Reads inside write transactions bypass Redis; SQL result caching is disabled around version lookup/miss computation. Redis failure falls back to PostgreSQL with bounded timeouts and no reconnect retry. [Details and constraints](../../CACHING.md).

The composite invoice ordering index was added, but the saved planner still preferred the existing customer index plus a small sort for this 1,000-invoice customer. Its standalone performance benefit is **not demonstrated**; do not attribute the HTTP improvement to that index alone. [Before plans](../2026-11-21-baseline-v1/query-plans.json), [after plans/indexes](query-plans.json), [recovery plans](recovery-plans.json). The balance query still aggregates authoritative ledger rows on a cache miss. Bullet includes a working lazy-association positive control; list/detail/balance checks found no N+1 on the existing paths, so no invented N+1 fix is claimed.

## Same read workloads, with cache state separated

Each endpoint independently receives 40 arrivals/s, five seconds warm-up, then 20 nominal seconds / **800 measured requests**. Paths remain customer 1 invoice pages 1 and 10 with `per_page=100`, and customer 1 balance. The open-loop Python client remains 32 threads / 64 in-flight tasks. There are no concurrent builds, tests or other benchmark scenarios during timed runs. All final reads have zero HTTP failures and zero capacity drops; response hashes match both baseline passes.

| Endpoint | Baseline p95, two passes (ms) | After, cache off p95 (ms) | After, warm p95, two passes (ms) | Cold application-cache observations, two singles (ms) |
| --- | ---: | ---: | ---: | ---: |
| `invoice_list_first` | 30.81 / 30.36 | 16.20 | 15.89 / 15.93 | 43.60 / 33.66 |
| `invoice_list_deep` | 756.52 / 53.32 | 18.15 | 11.12 / 10.46 | 8.92 / 21.69 |
| `customer_balance` | 40.26 / 95.32 | 17.23 | 10.98 / 12.07 | 17.90 / 43.46 |

The last column contains **one forced application-cache miss per endpoint/pass**, recorded before warm-up. It is not a cold-cache p95. PostgreSQL/OS buffers were never forcibly cleared. Each warm measured pass recorded **800/800 hits per endpoint**; the 25-second warm-up/measured interval fits inside the 30-second TTL. These are repeat hot-customer reads, not a claim about a diverse key population or cache expiration under sustained mixed writes.

SQL query counts fall from baseline 3/3/2 (first/deep/balance) to 2/2/2 on a hit (customer existence + uncached version read); a miss costs 4/4/3. Full p50/p95/p99, SQL timings, schedule-to-completion delays, first observations and every request are retained in [uncached](uncached-reads/summary.json), [warm](warm-reads/summary.json), [warm repeat](warm-reads-repeat/summary.json) and adjacent NDJSON files.

The unchanged-code baseline deep-page p95 varied from **53 to 757 ms**. Retaining both baseline passes avoids claiming a stable speedup from a shared-VM outlier. The three changes (removing recovery overhead, transport reuse, caching) are measured as a package; the uncached after-pass helps separate caching but is not a controlled per-change causal experiment.

## Same signed HTTP/Sidekiq workloads

The event mix, IDs, invoice pool and two distinct offered rates match the baseline: 10% repeated delivery IDs, another 10% distinct events for the same payment, and 100 separate warm-up payments. Events are durably received over HTTP and processed by actual Sidekiq/Redis against PostgreSQL and the local SDK/HTTP provider. Payment-effect counts exclude warm-up.

| Steady probe, 5 deliveries/s × 60 s | Baseline | Accepted image |
| --- | ---: | ---: |
| HTTP deliveries / failures / drops | 300 / 0 / 0 | 300 / 0 / 0 |
| Unique events processed | 270 | 270 |
| New payment effects | 240 | 240 |
| HTTP acknowledgment p95 | 132.86 ms | 47.27 ms |
| Receipt-to-last-attempt p95 | 121.26 ms | 28.96 ms |
| Event completion p95 | 414.23 ms | 87.89 ms |
| Final received / dead / review | 0 / 0 / 0 | 0 / 0 / 0 |

[Steady summary](steady-webhooks/summary.json) and queue samples contain actual elapsed-rate estimates and percentiles. A low offered rate does not establish maximum sustainable capacity. At one attempt, receipt-to-last-attempt approximates initial queue wait; retry delays alter that meaning.

| Overload probe, 100 offered deliveries/s × 60 s | Baseline | Accepted image |
| --- | ---: | ---: |
| Offered deliveries | 6,000 | 6,000 |
| Submitted / HTTP failures / client capacity drops | 3,447 / 0 / 2,553 | 5,985 / 0 / 15 |
| Unique accepted events | 3,160 | 5,387 |
| Unique processed at end of offering | Not fully sampled | 4,917 |
| Processed / received at drain endpoint | 1,101 / 2,059 | 5,387 / 0 |
| Fully drained by 180-second post-offering deadline | No | True |
| Measured new payment effects | Incomplete | 4,790 of 4,790 expected accepted identities |
| Completion p95 at final observation | Incomplete | 4931.78 ms |

[High-rate summary](high-webhooks/summary.json) includes HTTP/scheduling tails, backlog, retries/dead/review, full accounting and actual rate estimates. [Queue samples](high-webhooks/queue-samples.ndjson) preserve the entire observation period. End-of-offering processing is **4,917 unique events**, with 15 client capacity drops. Using the actual offering/tail window gives 4871.06 completed unique events/minute; including drain gives 4983.24/minute over 64.86 seconds. Neither reaches 5,000/minute. The high-rate harness exits 1 because its zero-capacity-drop acceptance condition is not met, despite full processing drain and zero HTTP failures. A short burst followed by drain does not establish sustained 100/s processing. The fixed workload reveals remaining CPU/database/provider work under the same resource limits; this milestone does not tune those caps to manufacture the target.

## Failure retained and transport correction

A complete earlier optimized candidate stalled at **902 processed / 4,465 pending** with 1,021 descriptors against the unchanged 1,024 soft limit. Worker logs show `Errno::EMFILE`. Creating a new SDK client per job accumulated retained transport pools. The candidate's [raw failure](candidate-failure/high-webhooks/summary.json), [worker sample](candidate-failure/high-worker-sample.txt), [descriptor observation](candidate-failure/descriptor-observation.json), source and image identities are preserved rather than omitted.

The accepted gateway reuses one SDK client per worker thread and replaces that bounded slot on configuration changes. It continues validating credentials on every initialization. Regression tests cover repeated use, thread separation, changed credentials and missing-key failure. The accepted load run completed substantially more event processing without the descriptor stall; [descriptor snapshot](worker-descriptors.json) reports 24 open descriptors afterward. The file limit was not raised. The SDK's [official source](https://github.com/stripe/stripe-ruby) and locally pinned 21.1.0 connection-manager/configuration code informed this diagnosis.

## Redis outage and full correctness replay

The [actual outage check](cache-outage.json) stopped isolated Redis, committed a payment through real reconciliation/SDK-local-HTTP, and verified a database-backed balance while Redis was unavailable. After restart the new version returned the correct cached balance. Customer version moved from 224 to 226; an old cache entry survived restart: **True**. Its old value did not become current again. Ordinary development services and the real sandbox were untouched by this check.

An initial full replay completed with the correct database effects but its observer reused old Active Record SQL-cache results, so its `final` count fields repeated the initial state. The [original report](full-replay-initial-report.log) and [fresh independent database audit](full-replay-fresh-audit.log) are retained. The verifier now runs snapshots under `uncached`; a real committed-write regression reproduces the stale-observer positive control. The entire 180,000-delivery replay was repeated on the separately tagged `ledgerly-benchmark:replay-verified` image after that evidence-only fix. The timed workload image and raw results were preserved.

The separate [all-invoice replay](full-replay.json) retains the same 50,000 invoices/usage/issuance journals but resets historical payments/refunds/receipts first. Every invoice then receives a paid notification; 5,000 also receive a refund event and 5,000 a stale failure event. Each of the **60,000 distinct events** is delivered three times in globally shuffled order: **180,000 signed deliveries**, with four concurrent workers. This is a service-level correctness exercise through real signature verification, durable receipt storage, locking and accounting; the canonical provider is in-process. It **does not measure HTTP/Sidekiq or real Stripe throughput**.

Actual result: **0 replay failures**, 50,000 unique payments, 5,000 unique refunds, 105,000 journals / 210,000 balanced rows, and all 60,000 receipts processed. All eight accounting checks report zero violations and receivables sum to zero separately per currency. Processing elapsed 356.22 seconds; this elapsed service time is not a throughput resume claim. Payment origin event types in the JSON confirm that refund/failure-first ordering occurred. Direct processing leaves dispatch intents; these are not presented as a Sidekiq drain measurement. The mixed fixture was restored afterward.

This supports duplicate-prevention claims for these tested identities/orderings and the suite's concurrency/crash cases, not a universal assertion that duplicate charges are impossible. The full replay creates no outgoing payment/charge operations; real outgoing collection was demonstrated separately in [Milestone 2](../../verification/milestone-2/README.md).

## Quality and retained state

[Final fresh-schema local checks](checks-final.log): **221 specs, zero failures; 142 Ruby files lint clean; scoped Sorbet and Rails autoload pass**. SimpleCov application lines **1,032/1,064 (96.99%)**, branches **229/269 (85.13%)**. Benchmark-only helpers under `lib/` remain outside application-only coverage; Sorbet still covers the explicitly scoped value objects rather than all billing services. The timed image passed [220 specs / 141 linted files](checks.log) before measurement; the extra final example covers the benchmark observer. Milestone 4 expands typing and release checks.

[Main-stack verification](main-stack-health.json) records the refreshed ordinary development stack and worker smoke, with financial counts unchanged. Benchmark services are stopped with the restored 50k fixture retained in their separate volumes. [Artifact manifest](artifact-manifest.json) hashes this report and all saved evidence. These remain short local runs on shared hardware; results should be repeated on controlled deployment resources before production capacity claims. No staging, commits or pushes occurred; HEAD remains the recorded base revision.
