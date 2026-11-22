# Milestone 1 verification — 2026-11-21

Core application source at `2a1aa1d721744a681308e4d00eaac1be7bdec048` passed the acceptance checks below. Progress and remaining scope are tracked in [ROADMAP.md](../../../ROADMAP.md); contracts are documented in [API.md](../../API.md) and [BILLING_RULES.md](../../BILLING_RULES.md).

## Results

| Check | Actual result | Evidence |
| --- | --- | --- |
| Full clean-checkout suite | 138 examples, 0 failures | [Clean-checkout output](clean-checks.txt) |
| Application line coverage | 447/456 lines, 98.02% | [SimpleCov output](clean-checks.txt); generated local HTML at `app/coverage/index.html` |
| Branch coverage | 88/94 branches, 93.61% | [SimpleCov output](clean-checks.txt) |
| Lint | 73 Ruby files, no offenses | [Clean-checkout output](clean-checks.txt) |
| Sorbet | Passing; current scope remains `app/value_objects` | [Clean-checkout output](clean-checks.txt) |
| Rails eager loading | `zeitwerk:check` passed | [Clean-checkout output](clean-checks.txt) |
| Fresh schema load | All constraints and tests passed after `db:create db:schema:load` in a new isolated database | [Clean-checkout output](clean-checks.txt) |
| Development stack | PostgreSQL, Redis, API and Sidekiq healthy; setup exited 0 | [Service snapshot](clean-services.txt) |
| Worker regression smoke | Rails → Redis → Sidekiq → PostgreSQL → Redis passed on the updated main stack | [Worker output](worker-smoke.txt) |
| Hosted CI | Successful Ubuntu x86_64 run for the tested source | [Run metadata](github-ci.json), [GitHub Actions](https://github.com/amovingman/Ledgerly/actions/runs/44964611834) |
| Live HTTP duplicates | Four concurrent usage requests → one event; four invoice requests → one invoice; each group returned one 201 and three 200 responses | [Live results](http-smoke.json), [reproducible client](http_smoke.py) |
| Live accounting | Invoice amount 70 minor units; one issuance journal, two rows, debit 70 = credit 70; receivable USD 70 | [Live results](http-smoke.json) |
| Live closure/replay | Original usage response unchanged after issuance; a new key for closed-period usage returned 409 | [Live results](http-smoke.json) |

This run establishes local usage/invoice idempotency and accounting behavior in the tested scenarios. Stripe collection, webhook reconciliation and duplicate-charge prevention under Stripe replay are not implemented or measured yet. No throughput, p95 improvement, or 50,000-invoice dataset claim is made.

## Automated scenarios

The committed RSpec suite exercises PostgreSQL uniqueness, checks, composite foreign keys and subscription exclusion constraints; normalized customer identity; price snapshots; authenticated endpoints; malformed input; strict integer quantities/prices; UTC timestamp normalization; scoped keys; changed payload conflicts; late usage and cancellation; exact billing boundaries; overflow; per-currency balances; and posting immutability.

Concurrency examples disable fixture transactions and use four actual PostgreSQL connections with a barrier. They verify one stored event for duplicate usage, one invoice/line/journal for duplicate issuance, rejection of overlapping contracts, and a simultaneous ingestion/issuance race that must either include accepted usage or reject it as closed. These examples clean their isolated test database before/after execution.

The rollback example injects a posting failure after usage allocation and asserts that invoice, line, allocation and journal all roll back. Another check rejects a second issuance journal even under a different business-effect key. Journal model checks reject unbalanced postings and attempts to append rows to an existing journal.

The full suite includes the prior foundation checks. Coverage refers to current `app/**/*.rb`, not migrations, Rails dependencies, future Stripe logic or the whole roadmap. Full model/service typing and coverage gates remain Milestone 4 work.

## Reproduce

From a clean GitHub clone, copy `.env.example` to `.env`, generate an API key as described in the root README, and run:

```sh
docker compose build api
docker compose up --no-build -d --wait
docker compose run --rm -e RAILS_ENV=test -e TEST_DB_DATABASE=ledgerly_m1_acceptance_test -e REDIS_URL=redis://redis:6379/1 api sh -c 'bin/rails db:create db:schema:load && bin/ci && bin/rails zeitwerk:check'
```

Schema loading replaces the contents of the named test database. Use the dedicated test name shown above. Application test guards reject development/production database names.

For the live acceptance check, use Python 3's standard library from the repository root:

```sh
python3 docs/verification/milestone-1/http_smoke.py
```

The client reads `API_KEY` from the environment or root `.env` and defaults to `http://127.0.0.1:3000`. It only accepts a local hostname and creates synthetic customer/plan/subscription/usage/invoice data on every run. It never invokes Stripe. To target a separate local port, set `API_BASE_URL`, for example `API_BASE_URL=http://127.0.0.1:3001`.

The recorded clean clone was under ignored `.tooling/m1-clean-checkout`, with Compose project `ledgerly-m1-clean`, host port 3001 and fresh database/Redis volumes. It used the ignored root `.env` explicitly via `--env-file`; application code, schema and dependencies came exclusively from the clean GitHub checkout. The temporary stack and its synthetic data were removed after verification; the main development stack remains available on port 3000.

Earlier batch evidence is retained in [models-and-schema.txt](models-and-schema.txt), [api-and-usage.txt](api-and-usage.txt), and [accounting-and-concurrency.txt](accounting-and-concurrency.txt).
