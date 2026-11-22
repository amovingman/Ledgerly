# Versioned billing read cache

This implements the caching task in [Milestone 3](../ROADMAP.md#milestone-3--baseline-load-and-optimization-week-3). PostgreSQL remains authoritative. Redis stores only serialized balance and paginated invoice-header responses.

## Keys and invalidation

Each customer has a monotonic `read_version`. Invoice creation, status/mapping changes, and journal creation advance it inside the same database transaction as the billing write. Rollback also rolls back the version change. After commit, readers select the new version and older keys are unreachable; there is no best-effort Redis deletion between commit and invalidation.

Keys use `ledgerly:reads:v1:<customer-id>:<read-version>:<resource>`. Every lookup obtains the version from PostgreSQL, even when given an older Customer instance. Cache misses calculate under `uncached` so Rails' SQL query cache cannot populate a new version from an older query result. A late fill can finish writing an old-version key, but later readers still use the new version. Reads overlapping a writer can return the earlier state; reads starting after commit use the committed version.

Reads inside a database transaction bypass Redis. The invoice collection mapping write takes the same customer-before-invoice lock order used by financial posting. Network/provider calls remain outside these write transactions. Header/version and journal/version changes are atomic, and existing effect uniqueness and immutable journal rules remain unchanged.

## Bounds and failures

- TTL: **30 seconds**, including old-version keys awaiting expiry.
- Maximum cached value: **64 KiB**; larger results return normally without being cached.
- Cached invoice pages: **1–10**, with the existing maximum 100 records per page. Later pages bypass Redis; validation/pagination behavior stays the same.
- Cached payloads are JSON values, not Active Record objects or executable serialization.
- `READ_CACHE_ENABLED=1` enables reads (the normal default); `0` bypasses the cache for diagnosis/comparison.
- Redis uses 20 ms connect/read/write timeouts and no reconnect retry. Failure falls back to PostgreSQL; a one-second per-process circuit avoids repeatedly blocking on a disconnected cache.
- Malformed cached JSON is ignored and falls back to PostgreSQL. Cache failures never undo committed billing writes.

The read cache shares the configured Redis service with development queues, with a separate key prefix. Size/TTL/page bounds limit individual entries; production cache capacity and queue isolation remain deployment work. Never flush the shared development Redis as a routine invalidation operation. The benchmark reset deliberately flushes its separate, disposable Redis only after workers stop.

Direct administrative SQL that changes financial records must also advance the affected customer version (and honor accounting invariants). Resetting versions is supported only by the guarded fixture reset, which clears the isolated cache. Normal API clients cannot set versions, money snapshots, Stripe mappings, or journal rows.

## Checks

The suite covers real Redis cache reuse/expiry, committed issuance, payments/refunds and failed statuses, rollback, late fills racing a writer, stale Active Record query-cache snapshots, oversized/deep-page bypass, malformed JSON, and Redis read/write failures. The separate benchmark integration check actually stops Redis, commits a synthetic payment through reconciliation while it is down, verifies database-backed reads, restarts Redis, and checks that an old cache entry cannot become current again.

Benchmark-only headers record cache hit/miss/off status. The benchmark-only authenticated `POST /_benchmark/cache/clear` clears only `ledgerly:reads:v1:*` keys to record one cold application-cache observation before warm-up. It is absent from ordinary development/production routes. This does not clear PostgreSQL or operating-system caches; cold-first observations are not cold-database percentiles.

Bullet 8.3.1 is pinned for development/test query checks. `BULLET_ENABLED=1` enables development request detection. RSpec includes a deliberately lazy-loading positive control and checks invoice list/detail/balance requests. The existing serializers were already free of N+1 queries on these paths; no N+1 fix is claimed where none was found.
