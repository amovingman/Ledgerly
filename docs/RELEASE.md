# Release and acceptance procedure

[ROADMAP.md](../ROADMAP.md) tracks acceptance. The release is a test-mode portfolio API. Source and measured evidence are published to [amovingman/Ledgerly](https://github.com/amovingman/Ledgerly); `.env`, private Stripe CLI state, coverage work files and local tooling stay ignored.

## Clean local checks

From a fresh checkout, follow [README setup](../README.md), build the image and start its dependencies. Then run a dedicated test database:

```sh
docker compose build api
docker compose up --no-build -d --wait
docker compose run --rm --no-deps \
  -e RAILS_ENV=test -e TEST_DB_DATABASE=ledgerly_release_test \
  -e REDIS_URL=redis://redis:6379/1 api bin/ci
docker compose exec -T api bin/smoke
docker compose exec -T api ruby script/core_smoke.rb
docker compose exec -T api bin/rails ledgerly:audit
docker compose exec -T api bin/rails ledgerly:status
```

`bin/ci` enforces coverage floors, runs the full suite, lint, static types, negative/positive type probes, RBI synchronization and autoload checks. Test database guards reject accidental development/production targets. Use separate disposable services for clean-schema acceptance or work alongside a sandbox; Redis DB 1 is a namespace, not physical isolation. The final local release evidence uses a separate Compose project with fresh PostgreSQL/Redis volumes and a credential-free source snapshot.

CI repeats these checks on Ubuntu and runs a separate clean Compose HTTP/worker job. [Workflow runs](https://github.com/amovingman/Ledgerly/actions/workflows/ci.yml) attach the exact commit identity and coverage artifacts. The [release evidence](verification/milestone-4/README.md) records pre-push local checks; the hosted run/coverage artifact identifies the final pushed revision without requiring a third documentation-only commit.

## End-to-end Stripe sandbox demo

Configure the claimed sandbox and signature listener using [STRIPE_RELIABILITY.md](STRIPE_RELIABILITY.md). Keep credentials in `.env`; do not put them in a command argument, source, issue or chat. The listener and API must share the same pinned webhook API version/signing secret. Recreate services after secret changes.

The existing deterministic verification runner exercises the actual local API and worker, creates/finalizes one Stripe invoice, triggers a test decline, pays that same invoice with a test card, issues two partial refunds totalling the capture, and replays the received events in reverse order three times:

```sh
# Choose a fresh label for a new synthetic demo; reuse it only to recover that run.
docker compose exec -T -e STRIPE_SMOKE_RUN_ID=release-demo-1 api \
  bin/rails runner - < docs/verification/milestone-2/sandbox-smoke.rb
```

The runner uses test-mode-only credentials and stable keys; its `m2` fixture prefix reflects its original creation, not a different application path. It produces real **simulated sandbox** payments/refunds and new local records. It does not process live money. Fee simulation can change the sandbox cash balance; the API's receivable balance remains a separate gross-ledger measure. Wait for reconciliation rather than treating collection acceptance as payment success. The final report must show one successful captured charge, one local payment, two refunds, four balanced journals/eight rows, zero receivables and safe duplicate replay. Preserve failures too; inspect before reusing a run label after interruption.

## Replay and evidence

Run load/replay only in the guarded [benchmark stack](BENCHMARKS.md). All-invoice replay resets the isolated fixture's financial history, verifies 180,000 signed deliveries using real persistence/processor services with an in-process canonical provider, then restores the mixed fixture. It is not a live Stripe or HTTP/Sidekiq throughput test. Do not silently replace the historical performance report with later correctness timing.

Evidence should include source hashes/base revision, image identity, clean schema setup, complete check outputs, actual coverage scope, API/worker smoke, ledger audit, sandbox report, replay/accounting totals and service shutdown state. Exclude tokens, signing secrets, raw card data and real customer payloads. [Resume evidence rules](RESUME.md) distinguish tested scenarios from universal guarantees.

## Publishing and completion

The user requested two logical commits on 2026-11-22. Commit `5976771` publishes the previously verified Stripe/recovery and 50k benchmark work. The second commit contains Milestone 4 contracts, CI, docs and release acceptance. Push without rewriting unrelated history; confirm the remote SHA and hosted checks. No additional GitHub release/tag or production deployment is implied by these source pushes.

Keep the benchmark target honest: the saved high-rate probe had 15 client drops and did not demonstrate 5,000 processed unique events/minute. Milestone 3 performance belongs to its saved source/image and cache/resource conditions; Milestone 4 acceptance proves correctness/type/quality gates, not a newly measured latency claim after signatures.
