# Reproduction

Use [ROADMAP.md](../../../ROADMAP.md) and this directory's report for measured scope and outcomes. Python 3.9+ uses only the standard library; Ruby/dependencies are pinned in the Docker build. All commands run from the repository root. Do not run builds, profiles or test suites during timed offerings.

The measured source is identified by `images.json`, both `*-image-source.json` files and `source-comparison.json`. `optimized-source.tar.gz` contains public application/benchmark source, with its contents hashed in `optimized-source-manifest.json`. It excludes local secrets, runtime directories and locally generated encrypted credentials. The baseline production application is published commit `c9ed621c77b2384d056c69cf17dde86be739c81c`; its only changed existing image file is benchmark-only clock instrumentation. Profile/preparation helpers are additional benchmark files. Image IDs identify local measured builds; rebuilding need not produce identical image IDs.

Build an optimized image from the archived source in a temporary directory, or from the corresponding local working tree:

```sh
docker build -t ledgerly-throughput:optimized app
python3 -m unittest discover -s scripts -p test_sustained.py
```

For the release comparison, build `ledgerly-throughput:release` from a clean archive of `c9ed621`, adding only the three exact files in `release-observers.tar.gz` (the benchmark `metrics.rb` clock field and two preparation/profile scripts). `release-image-source.json` records every measured file hash. Keep production files at their release versions. The diagnostic helpers do not run in the measured worker.

Start the isolated dependencies and create the ordinary seed if it does not exist. Set variables explicitly for every session; the Compose default image name refers to the older Milestone 3 baseline.

```sh
export BENCHMARK_IMAGE=ledgerly-throughput:release
export BENCHMARK_THREADS=5 READ_CACHE_ENABLED=0
docker compose -f compose.benchmark.yaml up --no-build -d --wait \
  benchmark-postgres benchmark-redis benchmark-provider
docker compose -f compose.benchmark.yaml run --rm --no-deps seed
```

Prepare a fresh-payment variant before **each** independent load/profile, stopping applications first. The preparation deliberately deletes benchmark receipts/payment/refund effects, resets statuses/read versions, clears dedicated Redis, analyzes tables, checks accounting and prints table fingerprints. It keeps invoice/usage/issuance identities; unlike the original full SQL seed reset, invoice `updated_at` values from preceding writes remain. Consequently ten of eleven preparation table fingerprints match; invoice timestamp fingerprints vary. This comparison does not claim byte-identical tables or flushed database/OS caches. Counts, amounts, allocations and issuance identities are checked on every preparation.

```sh
docker compose -f compose.benchmark.yaml stop api sidekiq recovery
docker compose -f compose.benchmark.yaml run --rm --no-deps seed \
  bin/rails runner script/benchmarks/prepare_sustained.rb
# Optional sequential diagnostic; prepare again afterward before timed load.
docker compose -f compose.benchmark.yaml run --rm --no-deps seed \
  bin/rails runner script/benchmarks/profile_sustained.rb
```

After preparation:

```sh
docker compose -f compose.benchmark.yaml up --no-build --no-deps -d --wait api sidekiq recovery
python3 scripts/sustained.py --rate 100 --duration 300 \
  --workers 64 --max-inflight 256 --run-id release_repeat \
  --image "$BENCHMARK_IMAGE" --output /tmp/ledgerly-release-before
```

The command exits 1 when **any** predeclared pass criterion fails, even when throughput exceeds 5,000/min. Keep that report. For the matched optimized offering, stop the applications, select the optimized image/eight threads, prepare the variant again, restart only the applications and use a new output directory/run ID:

```sh
export BENCHMARK_IMAGE=ledgerly-throughput:optimized BENCHMARK_THREADS=8
# Stop, prepare and start as above; provider/dependency containers stay unchanged.
python3 scripts/sustained.py --rate 100 --duration 300 \
  --workers 64 --max-inflight 256 --run-id optimized_v2 \
  --image "$BENCHMARK_IMAGE" --output /tmp/ledgerly-optimized-100rps
```

The longer confirmation uses the same optimized image/concurrency/client and fresh preparation, offering 95 deliveries/s for 420 seconds. This offers 5,130 distinct events/min rather than 5,400, and is a separate capacity scenario rather than the matched before/after comparison:

```sh
python3 scripts/sustained.py --rate 95 --duration 420 \
  --workers 64 --max-inflight 256 --run-id confirmation_v1 \
  --image "$BENCHMARK_IMAGE" --output /tmp/ledgerly-confirmation
```

Final-image quality checks use a different database/Redis namespace:

```sh
docker compose -f compose.benchmark.yaml run --rm --no-deps \
  -e RAILS_ENV=test -e TEST_DB_DATABASE=ledgerly_throughput_test \
  -e REDIS_URL=redis://benchmark-redis:6379/1 seed bin/ci
```

Restore the ordinary mixed fixture and stop the benchmark services after testing:

```sh
docker compose -f compose.benchmark.yaml stop api sidekiq recovery
docker compose -f compose.benchmark.yaml run --rm --no-deps -e RESET_BENCHMARK_DATA=1 seed
docker compose -f compose.benchmark.yaml stop
curl --fail http://127.0.0.1:3000/ready
```

Expected restored counts/fingerprints are saved in the original baseline report. Benchmark credentials are synthetic, provider operations are read-only and the worker network cannot reach external Stripe. Never substitute production credentials or databases.

## Separate four-vCPU experiment

The two-vCPU longer run was not a sustained-capacity pass. A separate experiment temporarily increased the Ledgerly-only Colima profile from two to four vCPUs, retaining 4 GiB configured memory and all existing container CPU/memory caps. Its application image, eight-thread settings, fixture, client, provider code and 100/s offering match the optimized scenario; duration is seven minutes. This is additional hardware allocation, not a code-only improvement. Record the original allocation and stop both Ledgerly stacks cleanly before restarting that dedicated VM:

```sh
docker compose -f compose.benchmark.yaml stop
docker compose stop
colima -p ledgerly stop
colima -p ledgerly start --cpus 4 --memory 4
docker compose start postgres redis
docker compose start api sidekiq recovery
# Start isolated dependencies, prepare the fresh variant, and start benchmark
# applications with BENCHMARK_IMAGE=ledgerly-throughput:optimized and
# BENCHMARK_THREADS=8 as above.
python3 scripts/sustained.py --rate 100 --duration 420 \
  --workers 64 --max-inflight 256 --run-id scaled_4cpu_v1 \
  --image "$BENCHMARK_IMAGE" --output /tmp/ledgerly-scaled-4cpu
```

Afterward, restore the ordinary mixed fixture, stop both stacks, restore the original two-vCPU/four-GiB VM allocation, restart the original development containers and verify readiness/accounting. Do not change an unrelated shared VM to reproduce this test. The saved environment files distinguish the two resource allocations; application/provider/database cgroup limits remain unchanged.
