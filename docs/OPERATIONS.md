# Local operations and recovery

Follow [ROADMAP.md](../ROADMAP.md), [billing rules](BILLING_RULES.md), [cache contracts](CACHING.md) and [Stripe recovery](STRIPE_RELIABILITY.md). Commands below run against the ordinary development stack. Load testing and destructive fixture resets belong only to the separate [benchmark environment](BENCHMARKS.md).

## Health, queues and durable work

```sh
curl --fail http://127.0.0.1:3000/up
curl --fail http://127.0.0.1:3000/ready
docker compose ps -a
docker compose exec -T api bin/smoke
docker compose exec -T api bin/rails ledgerly:status
docker compose exec -T api bin/rails ledgerly:audit
```

`/up` checks application liveness. `/ready` requires PostgreSQL and Redis; it can return 503 during a Redis outage even while financial data remains durable. `bin/smoke` verifies real Rails → Redis → Sidekiq → PostgreSQL → Redis execution. `ledgerly:status` shows event/collection states, undispatched outbox count/oldest timestamp, the `webhooks` and `billing` queue depths, oldest webhook job age, retry size and dead-set size. It omits job arguments, raw payloads and provider credentials. A Redis failure is reported as `redis_unavailable` while database counts remain available.

| Observation | What to inspect |
| --- | --- |
| Undispatched outbox grows | Redis connectivity, `available_at` backoff, independent recovery heartbeat and dispatcher logs |
| Received receipts / pending collections remain old | Worker health, queue age, `last_attempted_at`, safe `last_error`, provider mapping and retry budget |
| `review`, `dead`, or Sidekiq dead set grows | Original failure and canonical provider state; resolve the cause before targeted replay |
| High queue age under load | Both queue depths and worker CPU/database pressure; accepted HTTP delivery is not completed processing |
| Ledger audit is nonzero | Preserve evidence, stop affected collection/replay work and investigate before further posting |
| Cache is unavailable | Read endpoints fall back to PostgreSQL; durable dispatch waits for Redis recovery |

There is no production alerting deployment in this portfolio release. Choose operational thresholds for the actual environment; a count of pending work by itself does not prove failure. Recovery runs every 15 seconds and requeues dispatches/attempts stale for five minutes. The eight-attempt retry budget and 23-hour ambiguous-create guard still apply. Backoffs can make an undispatched record intentionally unavailable for a time.

## Financial integrity audit

`ledgerly:audit` uses a fresh, read-only PostgreSQL **repeatable-read** snapshot with the observer SQL query cache disabled. It checks invoice totals, usage allocation sums/ownership/periods, journal balance/currency, issuance identity, payment identity, refund caps/identity and invoice states. It works on ordinary billing data without the benchmark's fixed counts or three-events-per-line assumption. It prints violation counts and exits nonzero if any check fails; it never repairs money or edits journal rows. Run the audit in its own transaction context.

PostgreSQL row checks and unique indexes prevent many invalid writes, but journal totals span multiple rows. RSpec deliberately corrupts a row through administrative SQL to prove the audit detects a journal imbalance that row-level checks cannot detect. Another test removes a usage allocation while leaving journals balanced. Administrative access must preserve the same accounting rules as application code.

## Diagnose and recover

```sh
docker compose logs --tail=100 api sidekiq recovery
docker compose exec -T api bin/rails stripe:recover
docker compose exec -T api bin/rails 'stripe:replay_event[evt_example]'
docker compose exec -T api bin/rails 'stripe:replay_collection[123]'
```

Replace the sample event/invoice identity with the investigated record. Manual replay accepts only `dead`/`review` work. It preserves payloads, operation keys, first-attempt timestamps, provider IDs and prior financial effects. Do not delete receipts/journals, reset operation timestamps, or bypass the expired ambiguous-create guard to make a retry succeed. Sidekiq's dead record remains inspectable after an application replay.

Keep raw webhook bodies and Sidekiq arguments within trusted console/database access. The authenticated event metadata endpoint exposes processing state and safe errors. Do not paste credentials or raw customer payloads into issues or CI logs.

## Cache, database and shutdown

Committed invoice/journal changes atomically advance `customers.read_version`. Redis failures do not roll back money. Old cache keys expire after 30 seconds; normal invalidation never flushes the shared queue Redis. Direct administrative financial SQL must also advance affected customer versions. Do not reset versions outside the guarded fixture reset.

```sh
docker compose down
```

Ordinary named volumes survive shutdown. Export/test backup and restore procedures before any production use; this release does not claim a tested disaster-recovery deployment. Never run `down --volumes` against data you need. CI and disposable acceptance environments use their own project volumes and may remove them after saving evidence.
