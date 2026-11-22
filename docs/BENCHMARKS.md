# Dataset and benchmark measurements

Follow [Milestone 3 in ROADMAP.md](../ROADMAP.md#milestone-3--baseline-load-and-optimization-week-3). The baseline was recorded before optional indexes, query changes, or Redis read caching. The [optimized comparison](benchmarks/2026-11-21-optimized-v1/README.md) preserves matched after-runs, profiling, failures and full-dataset correctness replay. [The first baseline report](benchmarks/2026-11-21-baseline-v1/README.md) contains both read passes, a successful conservative-rate probe, and the overloaded higher-rate trial. Results are local measurements, not production capacity guarantees.

## Isolated environment

`compose.benchmark.yaml` uses its own image, PostgreSQL database/volume, Redis volume, and fixture credentials. It never reads the Stripe sandbox credentials in `.env`. Worker, provider, database, Redis, and recovery stay on an internal Docker network; only the API also joins an ingress network and publishes `127.0.0.1:3002`. The worker cannot reach external Stripe. The main development stack at port 3000 and its claimed sandbox data remain separate. CPU and memory still share the same 2-vCPU Docker VM with that idle stack; this is data/queue isolation, not dedicated benchmark hardware.

Rails uses a dedicated `benchmark` environment with eager loading, no code reloading, warning-level logs, and Rails `NullStore`; the explicit billing cache uses Redis independently. The baseline uses the accepted Milestone 2 billing paths. The optimized image adds the versioned read cache, filtered recovery selection, targeted indexes and bounded SDK client reuse. A benchmark-only middleware adds SQL-count/time response headers and authenticated observation endpoints. A benchmark-only Gateway initializer points the real pinned Stripe SDK at a local, read-only HTTP provider stub. Neither is enabled in development/test/production.

The stub represents canonical paid invoices, one full card payment per invoice, and deterministic succeeded refunds. Each provider request has a fixed **2 ms minimum** service delay. Network/SDK/serialization time is additional. All provider create/update/delete requests are refused; no actual Stripe charges occur. This measures local ingestion, database, queue, reconciliation, and posting capacity under this stub, not Stripe's latency or rate limits. Stripe advises using a mock for [load testing](https://docs.stripe.com/rate-limits#load-testing).

## Deterministic fixture

The fixed seed is **20261121**, fixture version `v1`. The generator bulk-inserts synthetic rows with application constraints and required indexes enabled, then runs aggregate accounting checks and samples the SQL/provider/fingerprint contract. It does not run the historical rows through HTTP or Sidekiq; measured webhook processing does use both.

| Entity | Initial count |
| --- | ---: |
| Customers | 1,000 |
| Plans / subscriptions | 80 / 1,460 |
| Invoices / invoice lines | 50,000 / 50,000 |
| Usage events | 150,000 |
| Payments / refunds | 40,000 / 5,000 |
| Journals / ledger rows | 95,000 / 190,000 |
| Processed seed receipts / dispatched outbox rows | 40,000 / 40,000 |

Invoices cover 50 completed UTC months from September 2022 through October 2026. Each subscription invoices one metric/month and each line aggregates three usage events with correctly calculated request fingerprints. USD, CAD, EUR, and GBP remain separate. Initial statuses: 37,500 paid, 2,500 fully refunded, 5,000 issued, 5,000 payment_failed. Another 2,500 paid invoices have partial refunds. There are no synthetic outgoing collection operation rows; the starting fixture models already-mapped billing history, not an outgoing collection benchmark.

The customer distribution is intentionally uneven: 10 customers × 1,000 invoices, 90 × 200, 400 × 25, and 500 × 24. The heavy endpoint customer has 1,000 invoices across 20 metrics, rather than placing all 50,000 under one artificial customer. The remaining months/subscription combinations are unique, and active metric contracts do not overlap.

Two complete rebuilds must have identical ordered-row fingerprints across the 11 recorded tables. Fingerprints use SHA-256 over ordered per-row PostgreSQL JSON MD5 hashes; they identify reproducibility, not a cryptographic authenticity guarantee. Counts include outbox records even though those are not among the 11 fingerprinted tables.

## Build, verify, and reset

From the repository root, with Docker/Compose and Python 3 available:

```sh
export BENCHMARK_IMAGE=ledgerly-benchmark:optimized
export READ_CACHE_ENABLED=0
docker compose -f compose.benchmark.yaml build seed
docker compose -f compose.benchmark.yaml up --no-build -d --wait
```

Compose defaults to the old `ledgerly-benchmark:baseline` image name for compatibility. Explicitly export `BENCHMARK_IMAGE` for **every** command in an optimized session. The original local measured image is also retained as `ledgerly-benchmark:unoptimized-20261121`; rebuilding from current source cannot recreate old source. Saved source/image manifests distinguish the runs.

The `seed` service prepares the schema, creates a fresh fixture, verifies it, and exits 0. Starting again verifies/reuses an existing valid fixture without appending records or clearing queued work. The explicit reset command destroys only data in the dedicated benchmark database/Redis; stop its application workers first:

```sh
docker compose -f compose.benchmark.yaml stop api sidekiq recovery
docker compose -f compose.benchmark.yaml run --rm --no-deps \
  -e RESET_BENCHMARK_DATA=1 seed
docker compose -f compose.benchmark.yaml up --no-build --no-deps -d --wait api sidekiq recovery
```

The seed guard rejects other Rails environments, inherited database URLs, unexpected database names/hosts, other Redis destinations, and non-fixture Stripe credentials. The seed's reset path uses one database transaction and an advisory lock, keeps constraints enabled, resets sequences, and clears the dedicated Redis after commit. Stop and rebuild on seeding failure before measuring. Dataset verification checks all invoice totals, usage allocations, journal balances/currencies, payment/refund identities, issuance journals, refund caps, and invoice states.

## Baseline sequence

Use a fresh output directory for each independent run. Run checks/preflight before timed measurements, and do not run test suites/builds/other benchmark scenarios concurrently with the timed workload.

```sh
# Separate test DB and Redis namespace; leaves the benchmark fixture intact.
docker compose -f compose.benchmark.yaml run --rm --no-deps \
  -e RAILS_ENV=test -e TEST_DB_DATABASE=ledgerly_m3_test \
  -e REDIS_URL=redis://benchmark-redis:6379/1 seed \
  sh -c 'bin/ci && bin/rails zeitwerk:check'

# Three event types, three deliveries each, shuffled concurrently on 100 invoices.
python3 scripts/benchmark.py replay --run-id replay_v1 --output /tmp/ledgerly-replay
```

Reset/restart the fixture using the commands above after preflight, so baseline reads begin from the identical initial financial state. Capture query plans and the original indexes:

```sh
docker compose -f compose.benchmark.yaml exec -T api \
  bin/rails runner script/benchmarks/inspect.rb > /tmp/ledgerly-query-plans.json

# Three independent read scenarios, each with five seconds warm-up.
python3 scripts/benchmark.py reads --rate 40 --duration 20 --warmup 5 \
  --output /tmp/ledgerly-baseline-reads

# 100 financial warm-up events, then a conservative 300-delivery baseline.
python3 scripts/benchmark.py webhooks --rate 5 --duration 60 --run-id steady_v1 \
  --output /tmp/ledgerly-baseline-webhooks

# Separately, on another fresh reset: capacity/overload probe.
python3 scripts/benchmark.py webhooks --rate 100 --duration 60 --run-id baseline_v1 \
  --output /tmp/ledgerly-overload-webhooks
```

Do not reset between read scenarios: they are read-only. The webhook scenario changes payment state, so **reset before repeating the entire workload**. Use the same seed, image identity, resources, parameters, workload, and cache preparation when comparing an optimized run later. Do not re-run a webhook scenario with the same IDs against mutated data and call it a fresh-payment comparison.

The read scenarios request customer 1's invoice list at pages 1 and 10, both with `per_page=100`, and the customer's ledger-derived balance. The first observation is recorded separately, but PostgreSQL/OS buffers are not forcibly cleared; it is **not a cold-cache measurement**. Warm measurements use a separate warm-up phase. The load generator uses fixed open-loop arrival times with 32 threads and at most 64 in-flight tasks; capacity drops, client scheduling delays, errors, and tail duration are disclosed. HTTP latency includes full response reading and client JSON parsing; scheduled-to-completion latency also includes load-generator delay.

The webhook run warms 100 distinct unpaid invoices outside its measured pool. Of the measured deliveries, 10% repeat an earlier event ID/payload; another 10% use distinct IDs for the preceding payment. A complete 300-delivery run therefore expects **270 unique events and 240 new payment effects**; a complete 6,000-delivery run expects **5,400 unique events and 4,800 new payment effects**. Both exclude the separate 100 warm-up payments. Client capacity drops reduce these expectations to the actually accepted event/payment identities. It records HTTP latency and acceptance, processed events during offering, drain time, backlog samples, oldest queued-job latency, receipt-to-attempt/completion percentiles, retries/dead work, and actual financial-effect deltas. Receipt-to-attempt uses the stored **last** attempted timestamp: it approximates first queue wait when attempts=1 and includes retry delays otherwise. The retry count is reported alongside it.

Every submitted request has an NDJSON result; client capacity drops are counted separately. Percentiles use linear interpolation of ordered observations. Queue observations are sampled every two seconds until drain. The current runner writes observations as it goes and preserves a summary on drain timeout; `--drain-timeout` defaults to 180 seconds. A nonzero exit for overload is a measured failure result, not a reason to discard the raw evidence. The first high-rate trial used the archived earlier runner, whose timeout lost its in-memory queue series; its raw HTTP results and deadline/resource/extra snapshots remain available. Accounting is checked again after processing. Out-of-order/concurrent preflight is a **100-invoice sample within the loaded 50,000-invoice database**, not a claim that all 50,000 invoices were individually replayed.

The query-plan script uses read-only `EXPLAIN (ANALYZE, BUFFERS, SETTINGS, FORMAT JSON)`. `ANALYZE` after fixture loading gives PostgreSQL normal planner statistics; it does not add indexes or rewrite queries. See PostgreSQL's [EXPLAIN](https://www.postgresql.org/docs/17/sql-explain.html) and [ANALYZE](https://www.postgresql.org/docs/17/sql-analyze.html) documentation.

## Matched optimized sequence

Use the exact rates, durations, parameters, worker concurrency, fixture seed and resource caps above. Reset before each independent pass and each webhook run. For uncached reads export `READ_CACHE_ENABLED=0`; for cached reads export `READ_CACHE_ENABLED=1` **before restarting API/worker/recovery**. Capture the SQL plans again without forcing planner choices.

```sh
# After the normal stopped-worker reset, start with the selected cache flag.
export BENCHMARK_IMAGE=ledgerly-benchmark:optimized
export READ_CACHE_ENABLED=1
docker compose -f compose.benchmark.yaml up --no-build --no-deps -d --wait api sidekiq recovery
python3 scripts/benchmark.py reads --rate 40 --duration 20 --warmup 5 --cold-first \
  --output /tmp/ledgerly-warm-reads
# Reset/restart, then repeat into a different output directory.
```

`--cold-first` clears only the application read-cache prefix before each first observation. It records **one miss**, then five seconds of warm-up and 800 measured requests. This is a cold application-cache observation, not a cold-database p95. PostgreSQL and OS caches remain uncontrolled. Keep both warm repeats and the uncached after-pass; do not select only the slowest baseline tail for comparison.

Profile an idle sweep and 20 reconciliations on a fresh mixed fixture, with the same seed-service limits, before timed measurements:

```sh
docker compose -f compose.benchmark.yaml run --rm --no-deps seed \
  bin/rails runner script/benchmarks/profile.rb > /tmp/ledgerly-profile.log
# Reset again because profiling posts 20 payments.
```

After matched HTTP/Sidekiq measurements, run the actual Redis stop/payment/read/restart check using `python3 scripts/cache_outage.py`. It changes one invoice in the isolated fixture and stops workers to keep its assertions stable. It writes its result to `.tooling/m3-optimized/cache-outage.json`.

The all-invoice correctness replay is a separate destructive fixture preparation, guarded to the benchmark database. It retains all 50,000 invoices/issuance journals but resets historical payments/refunds/receipts, marks invoices issued, resets read versions and clears the isolated Redis. Stop the application services first:

```sh
docker compose -f compose.benchmark.yaml stop api sidekiq recovery
docker compose -f compose.benchmark.yaml run --rm --no-deps seed \
  bin/rails runner script/benchmarks/full_replay.rb > /tmp/ledgerly-full-replay.log
```

The verifier disables the observer's Active Record SQL query cache, so final snapshots see commits made on replay worker connections. This signs and verifies 180,000 globally shuffled deliveries representing 60,000 events (50,000 paid, 5,000 refund and 5,000 stale failed notifications), with four concurrent workers. It uses real PostgreSQL and production receipt/processor/posting services with an **in-process** canonical provider. It measures correctness, **not HTTP/Sidekiq or real Stripe throughput**. All original 50,000 invoice identities participate; expected final effects are 50,000 payments, 5,000 refunds, 105,000 journals and 210,000 ledger rows. Restore the mixed fixture with the guarded reset afterward. Its direct processing leaves outbox dispatch intents that were not consumed by Sidekiq; do not report these as a drained queue experiment.

## Evidence and cleanup

Save environment/resource limits, base Git revision and local source hashes, image ID, fixture fingerprints/counts, raw per-request results, queue samples, plans/indexes, final accounting, and a results summary together under `docs/benchmarks/<run-id>/`. Since publishing is suspended, the source identity is a local SHA-256 manifest rather than a newly created commit. Short local runs on a shared Docker VM are exploratory baselines; disclose the resource sharing and repeat runs before stronger capacity claims.

```sh
# Stop while retaining the benchmark dataset/volumes.
docker compose -f compose.benchmark.yaml stop
# Remove only the disposable benchmark stack and its volumes if no longer needed.
docker compose -f compose.benchmark.yaml down --volumes
```

The ordinary `docker compose` stack and claimed Stripe sandbox are unaffected by benchmark cleanup. Cache contracts and failure behavior are documented in [CACHING.md](CACHING.md).
