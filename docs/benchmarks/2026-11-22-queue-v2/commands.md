# Reproduce queue-spike experiments

Use [ROADMAP.md](../../../ROADMAP.md) and the report for exact results/resource scope. Existing historical evidence is immutable. All load uses fixture credentials on the isolated benchmark network and the read-only local provider. Commands run at the repository root with Docker Compose and Python 3.9+.

Use a dedicated four-vCPU/four-GiB Docker VM, retaining an idle development stack as in the measurement. The prior report documents the temporary Colima `ledgerly` profile allocation/restoration. Build the archived application source as `ledgerly-queue:profile`:

```sh
docker build -t ledgerly-queue:profile app
export BENCHMARK_IMAGE=ledgerly-queue:profile READ_CACHE_ENABLED=0
export BENCHMARK_THREADS=8 BENCHMARK_PROFILE_SPIKES=1
export BENCHMARK_WORKER_THREADS=8
export BENCHMARK_DB_CPU_PERIOD=100000 BENCHMARK_DB_CPU_QUOTA=100000
docker compose -f compose.benchmark.yaml up --no-build -d --wait \
  benchmark-postgres benchmark-redis benchmark-provider
```

If the original 50k seed does not exist, run the seed service first. Before **each** independent profile/load, stop benchmark applications and prepare the fresh-payment variant:

```sh
docker compose -f compose.benchmark.yaml stop api sidekiq recovery
docker compose -f compose.benchmark.yaml run --rm --no-deps seed \
  bin/rails runner script/benchmarks/prepare_sustained.rb
```

The original ordinary fixture has 40k payments/5k refunds; the fresh variant deletes these effects, retains invoice/usage/issuance identities, resets invoice statuses/read versions, clears dedicated Redis, analyzes tables and checks accounting. Invoice `updated_at` values retain preceding write history, so invoice timestamp fingerprints differ between partial preparations; amounts/allocations/identities are checked and the other ten fingerprints match. PG/OS caches are not explicitly flushed.

The one-process baseline uses `BENCHMARK_WORKER_THREADS=8` and `--scale sidekiq=1`. The four-thread candidate uses `BENCHMARK_WORKER_THREADS=4` and `--scale sidekiq=2`; the failed twelve-thread experiment uses `BENCHMARK_WORKER_THREADS=6` with the same two processes. API threads stay at eight. Retain the aggregate worker CPU/memory increase when describing these results.

```sh
docker compose -f compose.benchmark.yaml up --no-build --no-deps -d --wait \
  --scale sidekiq=2 api sidekiq recovery
python3 scripts/sustained.py --rate 100 --duration 420 --workers 64 \
  --max-inflight 256 --run-id unique_run_id --image "$BENCHMARK_IMAGE" \
  --output /tmp/ledgerly-queue-run
# Run these even when the original load gate exits 1; retain every miss.
python3 scripts/queue_timeline.py --image "$BENCHMARK_IMAGE" \
  --directory /tmp/ledgerly-queue-run
python3 scripts/check_queue_run.py --directory /tmp/ledgerly-queue-run
```

`check_queue_run.py` preserves the complete original sustained gate and additionally requires **both** pending-peak estimates to be strictly below 100. A timestamp estimate of 127 is a miss even if five-second samples peaked at 31. Missing reports raise an error; they cannot produce a pass.

The PostgreSQL smoothing experiment uses two × four worker threads and **10,000 µs quota / 10,000 µs period**, keeping the same one-core allowance. Stop applications first, then recreate only the benchmark PG container on its retained volume; verify its kernel limit before preparing/restarting applications:

```sh
export BENCHMARK_WORKER_THREADS=4
export BENCHMARK_DB_CPU_PERIOD=10000 BENCHMARK_DB_CPU_QUOTA=10000
docker compose -f compose.benchmark.yaml stop api sidekiq recovery
docker compose -f compose.benchmark.yaml up --no-build --no-deps -d --wait benchmark-postgres
docker exec ledgerly-benchmark-benchmark-postgres-1 cat /sys/fs/cgroup/cpu.max
# Expected: 10000 10000. Prepare the variant, restart apps and run as above.
```

This restarts PostgreSQL; shared-buffer state can differ. The clean two-worker confirmation retained that PG instance and changed only `BENCHMARK_PROFILE_SPIKES=0` before preparing/restarting applications; it missed the denser guard. The accepted clean run keeps profiling disabled, retains four threads/process and uses **`--scale sidekiq=3`**. Aggregate worker caps are then 3 CPUs/1.5 GiB, with twelve total worker threads. Keep the same PG 10000/10000 settings and fresh preparation. The provider minimum delay and database durability/correctness settings are unchanged.

`monitor.py` launches persistent shells to save approximately one-second cgroup throttling, CPU/I/O pressure and VM CPU-pressure samples. Run with `--workers 1` or `2` as appropriate, `--output` for its filename prefix, `--until` pointing to the new run's summary and `--seconds 450`. For instrumented runs, copy each worker's `/tmp/ledgerly-queue-profile.ndjson` after completion. `analyze.py` summarizes thresholded slow-job examples and nearby counters; these are diagnostic observations, not a complete job-latency distribution.

Quality checks run before timed offerings in a separate test DB/Redis namespace:

```sh
docker compose -f compose.benchmark.yaml run --rm --no-deps \
  -e RAILS_ENV=test -e TEST_DB_DATABASE=ledgerly_queue_test \
  -e REDIS_URL=redis://benchmark-redis:6379/1 seed bin/ci
python3 -m unittest discover -s scripts -p 'test_*.py'
```

Restore afterward: stop apps, run seed with `RESET_BENCHMARK_DATA=1`, verify all 11 original fingerprints, restore PG's 100000/100000 period/quota and stop benchmark services. Restore the original two-vCPU/four-GiB dedicated VM, restart the existing development services, and verify readiness/unchanged financial audit. Do not alter an unrelated shared VM or use real Stripe credentials.


Accepted clean command after preparation, with `BENCHMARK_PROFILE_SPIKES=0`, `BENCHMARK_WORKER_THREADS=4`, `BENCHMARK_THREADS=8`, and both DB quota variables set to 10000:

```sh
docker compose -f compose.benchmark.yaml up --no-build --no-deps -d --wait \
  --scale sidekiq=3 api sidekiq recovery
python3 scripts/sustained.py --rate 100 --duration 420 --workers 64 \
  --max-inflight 256 --run-id queue_three_final_v1 --image "$BENCHMARK_IMAGE" \
  --output /tmp/ledgerly-three-workers
python3 scripts/queue_timeline.py --image "$BENCHMARK_IMAGE" \
  --directory /tmp/ledgerly-three-workers
python3 scripts/check_queue_run.py --directory /tmp/ledgerly-three-workers
```
