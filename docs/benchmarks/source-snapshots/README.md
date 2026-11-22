# Reconstructing the measured source

[ROADMAP.md](../../../ROADMAP.md) and [the benchmark guide](../../BENCHMARKS.md) define scope and safety. Earlier measurements were made while commits were suspended. Milestone 4 publishes their source without inventing a historical commit.

## Original baseline

[baseline-2026-11-21.tar.gz](baseline-2026-11-21.tar.gz) contains **157 public application source files** recovered offline from the retained measured image `sha256:86ce22b8cb9f3c1f86c571e3ade20f3109be06f1be7b1df9a9a512fd8f4d0d99`. Every file matches [the original source manifest](../2026-11-21-baseline-v1/source-manifest-original.json). Docker-ignored `log/.keep` and `tmp/.keep` are omitted. [Archive manifest](baseline-manifest.json) records the archive checksum and member hashes. The archive contains source, not environment files, database volumes, gem binaries, private CLI state or a registry image.

From the repository root:

```sh
mkdir -p /tmp/ledgerly-before
tar -xzf docs/benchmarks/source-snapshots/baseline-2026-11-21.tar.gz -C /tmp/ledgerly-before
docker build -t ledgerly-benchmark:baseline-rebuild /tmp/ledgerly-before/app
export BENCHMARK_IMAGE=ledgerly-benchmark:baseline-rebuild
export READ_CACHE_ENABLED=0
# Destructive only to the separate disposable benchmark volumes. Save needed evidence first.
docker compose -f compose.benchmark.yaml down --volumes
docker compose -f compose.benchmark.yaml up --no-build -d --wait
```

Use fresh benchmark volumes when switching back to the old schema; resetting rows alone would retain the later indexes/cache-version column. The current Compose file has the same recorded resource caps and isolated fixture credentials. The old image ignores the newer cache flag. Run the saved rates/durations/IDs/parameters with a fresh output directory. The [archived original client](../2026-11-21-baseline-v1/harness-original.py) identifies the original overload trial; the current client retains queue/error evidence that the old timeout path lost. Its arrival scheduling and financial duplicate mix are unchanged.

## Optimized Milestone 3

Commit [5976771](https://github.com/amovingman/Ledgerly/commit/5976771de93b4dc938bb5f610a7999f259fb2ff8) publishes the accepted Milestone 3 implementation before Milestone 4 type contracts. Extract it without changing the current checkout:

```sh
mkdir -p /tmp/ledgerly-after
git archive 5976771 app | tar -x -C /tmp/ledgerly-after
docker build -t ledgerly-benchmark:optimized-rebuild /tmp/ledgerly-after/app
export BENCHMARK_IMAGE=ledgerly-benchmark:optimized-rebuild
```

The [optimized report](../2026-11-21-optimized-v1/README.md) records the timed image/source and the later observer-only verification fix. [The exact source delta](../2026-11-21-optimized-v1/verification-source-delta.json) shows that billing/controller/cache/recovery/SDK/database runtime code did not change between that timed image and the accepted source published in `5976771`.

Reset/start the isolated benchmark schema/fixture and follow [the exact accepted ordering](../2026-11-21-optimized-v1/commands.md), selecting cache off or on **before** restarting application services. Keep cold application-cache singles separate from warm percentiles. Record your own host/VM, image/dependency identity and raw results; later builds and shared hardware will not reproduce identical milliseconds.

The original evidence directories and artifact manifests remain unchanged. These additional snapshots make the source available; they do not replace or revise the historical measurements. Milestone 4 signatures are validated for correctness separately and have no newly claimed latency benchmark.
