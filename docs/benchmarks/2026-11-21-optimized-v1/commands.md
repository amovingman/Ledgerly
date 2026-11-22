# Accepted-image commands and ordering

See [ROADMAP.md](../../../ROADMAP.md) and [the general guide](../../BENCHMARKS.md). Run from the repository root. Local measured base revision: `23e0e76c90429375bcc6331d12ec1a171a642517`; executable identity is the source/image manifest, because commits are suspended. The original baseline artifacts were not rewritten. Baseline image remains locally tagged `ledgerly-benchmark:unoptimized-20261121`.

The following is the accepted run's ordering. Use a fresh output directory instead of overwriting saved evidence. No builds/checks/other scenarios run during timed HTTP benchmarks. The main development stack stays idle throughout timed measurements.

```sh
export BENCHMARK_IMAGE=ledgerly-benchmark:optimized
export READ_CACHE_ENABLED=0
out=/tmp/ledgerly-optimized
mkdir -p "$out"
docker compose -f compose.benchmark.yaml build seed
docker compose -f compose.benchmark.yaml up --no-build -d --wait benchmark-postgres benchmark-redis benchmark-provider

# Fresh schema-loaded quality check; dedicated test DB and Redis DB 1.
docker compose -f compose.benchmark.yaml run --rm --no-deps \
  -e RAILS_ENV=test -e TEST_DB_DATABASE=ledgerly_m3_accepted_test \
  -e REDIS_URL=redis://benchmark-redis:6379/1 seed \
  sh -c 'bin/rails db:prepare && bin/rails db:schema:load && bin/ci && bin/rails zeitwerk:check'

reset_fixture() {
  docker compose -f compose.benchmark.yaml stop api sidekiq recovery
  docker compose -f compose.benchmark.yaml run --rm --no-deps \
    -e RESET_BENCHMARK_DATA=1 seed
}
start_apps() {
  docker compose -f compose.benchmark.yaml up --no-build --no-deps -d --wait \
    benchmark-provider api sidekiq recovery
}

reset_fixture
docker compose -f compose.benchmark.yaml run --rm --no-deps seed \
  bin/rails runner script/benchmarks/profile.rb > "$out/profile.log"
# Profiling posts 20 payments; reset again before read comparison.
reset_fixture
start_apps
docker compose -f compose.benchmark.yaml exec -T api \
  bin/rails runner script/benchmarks/inspect.rb > "$out/query-plans.json"
python3 scripts/benchmark.py reads --rate 40 --duration 20 --warmup 5 \
  --output "$out/uncached-reads"

export READ_CACHE_ENABLED=1
reset_fixture
start_apps
python3 scripts/benchmark.py reads --rate 40 --duration 20 --warmup 5 --cold-first \
  --output "$out/warm-reads"
reset_fixture
start_apps
python3 scripts/benchmark.py reads --rate 40 --duration 20 --warmup 5 --cold-first \
  --output "$out/warm-reads-repeat"

# Reads don't change financial state; same fresh fixture for steady processing.
python3 scripts/benchmark.py webhooks --rate 5 --duration 60 --run-id steady_v1 \
  --output "$out/steady-webhooks"
reset_fixture
start_apps
python3 scripts/benchmark.py webhooks --rate 100 --duration 60 --run-id baseline_v1 \
  --drain-timeout 180 --output "$out/high-webhooks"
# Accepted-image high-rate run exits 1 for 15 client capacity drops, despite
# zero HTTP errors and full processing drain. Keep its summary/raw outputs.
# Run the remaining commands separately after inspecting that measured result.

python3 scripts/cache_outage.py
# This writes .tooling/m3-optimized/cache-outage.json; copy into the evidence set.
docker compose -f compose.benchmark.yaml stop api sidekiq recovery
export READ_CACHE_ENABLED=0
docker compose -f compose.benchmark.yaml run --rm --no-deps seed \
  bin/rails runner script/benchmarks/full_replay.rb > "$out/full-replay.log"
# Full replay is correctness-only: four threads, real PG/signature/posting,
# in-process canonical provider, no HTTP/Sidekiq throughput claim.

# Restore the original mixed financial fixture, then release benchmark CPU.
reset_fixture
docker compose -f compose.benchmark.yaml stop
```

All original business fingerprints must match before each independent timed run. The added `customers.read_version` counter is excluded from comparison; all original columns remain included. Record its zero initialization separately. Final source checks passed before these measurements; image/source comparison runs with Docker networking disabled.

The original baseline has a separately archived earlier Python runner for its overload trial. That runner lost its in-memory queue series on timeout. The accepted runner preserves samples and timeout summaries; arrival scheduling, rates, duplicate mix, IDs, invoice pool, worker counts, resource caps and drain limit are unchanged. Cached first observations intentionally add prefix-only application-cache clearing; baseline/uncached first observations do not establish cold database state.
