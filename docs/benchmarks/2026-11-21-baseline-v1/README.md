# Milestone 3: unoptimized baseline

Measured locally on **2026-11-21 America/Toronto** (raw UTC timestamps fall on November 22). [ROADMAP.md](../../../ROADMAP.md#milestone-3--baseline-load-and-optimization-week-3) tracks the remaining optimization work. [Benchmark instructions](../../BENCHMARKS.md) describe the fixture, isolation, reset, workloads, and definitions.

**The 50,000-invoice dataset and baseline phase are complete. No optional indexes, query rewrites, or read caching were added.** This is an exploratory local baseline, not a production capacity or before/after improvement claim.

## Data and source identity

- [Initial dataset counts](dataset-counts.json): 1,000 customers, 80 plans, 1,460 subscriptions, 50,000 invoices/lines, 150,000 usage events, 40,000 payments, 5,000 refunds, 95,000 balanced journals and 190,000 ledger rows. All eight accounting checks report zero violations.
- [Determinism](determinism.json): two full rebuilds have identical ordered-row fingerprints across all 11 fingerprinted tables. [First build](seed-first.json), [second build](seed-second.json), and [fresh repeat fixture](seed-repeat.json) are saved.
- [Unoptimized confirmation](unoptimized-confirmation.json): all 68 business-code/schema files checked against Milestone 2 are unchanged. Correctness indexes/foreign keys remain enabled.
- Base Git revision: `23e0e76c90429375bcc6331d12ec1a171a642517`; **all work is local and uncommitted**. No GitHub publishing or hosted CI run occurred. [Image ID](image-id.json), [offline image/source verification](image-source-verification.json), [original source manifest](source-manifest-original.json), and [current source manifest](source-manifest.json) pin the actual local executable state.
- After the high-rate timeout, only the Python evidence writer changed to retain samples/timeout summaries. The [original runner](harness-original.py) is archived for that trial. Application image, schema, SQL, resources and fixture algorithm were unchanged between timed runs.

## Environment

[Environment](environment.json), [container limits/networks](container-resources.json), and [service state](services.ndjson) record the setup. The ARM64 Docker VM has **2 vCPUs and about 3.81 GiB usable memory** (4 GiB configured). The ordinary development stack remained running and idle on that same VM; hardware was shared. Data, Redis queues, volumes and provider traffic were isolated.

The benchmark API/worker each have a 1-vCPU cap and 512 MiB memory limit; PostgreSQL 1 vCPU/768 MiB; provider 0.5 vCPU/128 MiB; recovery 0.5 vCPU/256 MiB; Redis 0.5 vCPU/128 MiB. These caps share the 2-vCPU VM, so they are not simultaneous dedicated CPU reservations. Sidekiq concurrency and API threads are both 5. The recovery loop stayed enabled throughout the measurements.

Rails uses eager loading/no reloading and `NullStore`; PostgreSQL/OS buffers were warmed normally and never forcibly flushed. There is no cold-cache result. The real pinned Stripe SDK talks only to the local read-only provider stub with a 2 ms minimum delay per request. The worker's network is internal; the API alone has loopback-published ingress. [Provider counters](provider-contract.json) confirm zero writes and 1,850 expected SDK GETs during the successful steady run including warm-up. No real Stripe load or payments were generated.

## Read baselines

Each scenario used **40 arrivals/second**, a **5-second warm-up**, then **20 nominal seconds / 800 measured requests**. The fixture was reset to matching fingerprints before the second pass. [Comparability checks](read-comparability.json) confirm identical request paths and response bodies across both passes. Endpoints were tested separately; no builds/specs/other workloads ran concurrently. First-observation and warm-up records are separate from measured results.

Client-observed HTTP latency, milliseconds, includes full body reading/JSON parsing. SQL query counts exclude schema introspection, transaction control and query-cache hits.

| Pass | Scenario | p50 ms | p95 ms | p99 ms | SQL queries/request |
| --- | --- | ---: | ---: | ---: | ---: |
| First | `invoice_list_first` | 7.55 | 30.81 | 81.60 | 3 |
| First | `invoice_list_deep` | 11.33 | 756.52 | 1370.18 | 3 |
| First | `customer_balance` | 12.65 | 40.26 | 95.06 | 2 |
| Repeat | `invoice_list_first` | 8.11 | 30.36 | 64.90 | 3 |
| Repeat | `invoice_list_deep` | 7.49 | 53.32 | 209.82 | 3 |
| Repeat | `customer_balance` | 13.22 | 95.32 | 212.38 | 2 |

Both passes had **zero HTTP failures and zero client capacity drops**, totaling 4,800 measured requests. Raw per-request timings, scheduled-to-completion delays, SQL timings and warm-up/first observations are in [first-pass results](reads/summary.json), [repeat results](reads-repeat/summary.json), and their adjacent NDJSON files.

The deep-page p95 varied from roughly **53 to 757 ms**, while balance p95 varied from **40 to 95 ms**. These are two runs of the same unoptimized code, not an improvement. The first deep-page run also had client start-delay p95 around 245 ms; its schedule-to-completion p95 was about 1,025 ms. Retain both runs and repeat on controlled resources before a stable latency or improvement claim.

[Query plans and original indexes](query-plans.json) include read-only `EXPLAIN ANALYZE/BUFFERS` for first/deep invoice pages, count and balance. One plan execution took about 1.68 ms (first list), 0.42 ms (deep list), 0.14 ms (count) and 52.45 ms (balance); these single diagnostic executions are separate from HTTP percentiles. HTTP tails cannot be attributed solely to the list sort from these results.

## Signed webhook baselines

The payload mix contains 10% repeated event IDs and another 10% distinct event IDs describing the preceding payment. There is a separate 100-payment warm-up on reserved invoices. Whole-dataset accounting checks run before/after each completed scenario. The incoming rate, unique event rate, and logical payment rate are distinct measures.

### Conservative steady-rate probe

[Full summary](steady-webhooks/summary.json), [raw requests](steady-webhooks/webhooks.ndjson), and [queue samples](steady-webhooks/queue-samples.json):

| Measurement | Actual result |
| --- | ---: |
| Offered workload | 5 deliveries/s for 60 nominal seconds |
| HTTP deliveries / failures / capacity drops | 300 / 0 / 0 |
| Duplicate acknowledgments | 30 |
| Unique events accepted and processed | 270 |
| New payment effects, excluding warm-up | 240, exactly as expected |
| New refund effects | 0; this timed scenario measures payments |
| Final pending / retries / dead / review | 0 / 0 / 0 / 0 |
| HTTP acknowledgment p50 / p95 / p99 | 23.52 / 132.86 / 221.66 ms |
| Receipt-to-attempt p50 / p95 / p99 | 18.69 / 121.26 / 276.14 ms |
| Event completion p50 / p95 / p99 | 101.01 / 414.23 / 922.38 ms |
| Sampled peak pending events | 3 |
| Sampled oldest queued-job latency peak | 0.000 s |

All events used one processing attempt. Receipt-to-last-attempt therefore approximates first queue waiting here. At higher retry counts it includes retry delays. Two-second queue samples can miss short peaks; zero sampled oldest-job latency does not mean every event began immediately. The run processed about **270 unique events/minute under this offered rate**, and 240 new payment effects per nominal minute. This low-rate probe does **not** establish maximum sustainable capacity. The raw helper also reports actual elapsed-rate estimates (roughly 59.97 seconds including observations); nominal-window counts above avoid overstating a rate from a slightly shorter last-arrival window.

[Final accounting](dataset-final.json) records the consistent final state (warm-up is recorded separately): 50,000 invoices, 40,340 payments (40,000 seed + 100 warm-up + 240 measured), 5,000 refunds, 95,340 journals and 190,680 ledger rows, with zero accounting violations. Payment identity uniqueness and balanced journals were preserved.

### High-rate overload probe

[Overload summary](overload/summary.json), [raw HTTP results](overload/webhooks.ndjson), [deadline error](overload/runner-error.txt), [extra queue observations](webhook-extra-observations.ndjson), and [resource snapshot](overload-resource-snapshot.ndjson) are retained.

At **100 offered deliveries/s for 60 seconds**, the 32-thread/64-in-flight client submitted 3,447 requests, all acknowledged with HTTP 200; **2,553 offered arrivals were dropped by the client before reaching the API**. There were 3,160 unique accepted events and 287 duplicate acknowledgments. At the 180-second post-offering drain deadline, **1,101 were processed and 2,059 remained pending** (2,054 queued plus active work). No dead/review/retry events were observed. Accounting still passed after workers were stopped for the snapshot.

This is an overloaded, incomplete-processing trial. It does not demonstrate 5,000 completed events/minute. Pending synthetic work was counted/preserved in evidence, then the disposable fixture was reset before the repeat/steady run. The earlier runner raised on drain timeout before saving its in-memory queue series; original source, request rows, deadline snapshot and extra observations remain, but there is no complete two-second queue series for this trial. The current runner fixes that evidence-writing limitation without changing application behavior.

## Correctness and quality checks

[Replay preflight](replay/summary.json): 900 concurrent shuffled deliveries of three event types across **100 sampled invoices in the 50,000-invoice database**, 300 distinct processed events, exactly 20 previously absent payments, zero accounting violations. Existing partial/full refund identities remained unique. This is not an all-50,000-invoice replay claim; that remains pending.

[Full local checks](checks.txt): **202 specs, zero failures**, randomized seed 45190; **131 Ruby files lint clean**, scoped Sorbet and Rails autoload passed. SimpleCov application line coverage is **952/985 (96.64%)**, branches **212/251 (84.46%)**; benchmark helpers under `lib/` are outside that application-only coverage scope. The suite includes a real-database regression for the observation endpoint's timing columns.

## Next work and retained state

The first six baseline/data tasks in Milestone 3 are complete. Optional indexes, Bullet-assisted query checks, read caching/invalidation, matched after-runs and all-50,000-invoice replay are unstarted. Profile before changing anything: the existing recovery sweep scans old dispatched records, and the overload snapshot shows it using about 43% of a CPU. That is a candidate cost to investigate, not proof of the sole bottleneck. Sorting only 1,000 invoice headers did not explain the full observed HTTP tails.

Benchmark services were stopped after evidence collection to release CPU; their named volumes retain the 50k fixture and the final consistent payment state. [Main-stack health](main-stack-health.json) confirms the ordinary development API/PostgreSQL/Redis remained healthy. Restart/reset commands are in [docs/BENCHMARKS.md](../../BENCHMARKS.md). No commits or pushes were made.
