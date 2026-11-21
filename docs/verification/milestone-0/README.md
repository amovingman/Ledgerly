# Milestone 0 verification — 2026-11-21

The application source and infrastructure at commit `70aea136d71ac1a3a18ab0d96bcfcab8e16ee2af` passed a clean-checkout boot and the checks below. See [ROADMAP.md](../../../ROADMAP.md) for scope and next work.

## Environment

- Host: macOS arm64; Ruby 3.4.13, Bundler 4.1.0.
- Docker 29.10.0, Compose 5.8.0, Colima 0.10.3; VM: 2 CPUs, 4 GiB RAM, 20 GiB disk.
- Containers: Ruby 3.4.13 on Debian bookworm, PostgreSQL 17.12, Redis 8.2.3.
- Sidekiq 8.1.7, concurrency 5; API and worker run as the nonroot `rails` user.
- Dependency versions: committed `app/Gemfile` and `app/Gemfile.lock`.

These are foundation checks, not load benchmarks. No usage ingestion, invoice generation, Stripe processing, throughput, or duplicate-charge result is established by this run.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| Clean GitHub clone and Docker build | Passed with frozen dependency lockfile | Commands below; clean clone had no local bundle configuration, installed gems, `.env`, or master key |
| Clean stack boot | PostgreSQL, Redis, API and Sidekiq healthy; setup exited 0 | [Service snapshot](clean-services.txt) |
| Real queued job | Rails → Redis → Sidekiq → PostgreSQL → Redis passed | [Worker output](clean-worker-smoke.txt) |
| RSpec | 44 examples, 0 failures | [Clean-checkout output](clean-checks.txt) |
| SimpleCov | 102/110 application lines, 92.72%; branches 29/30, 96.66% | [Clean-checkout output](clean-checks.txt); local HTML report at `app/coverage/index.html` (ignored generated file) |
| RuboCop | 41 files, no offenses | [Clean-checkout output](clean-checks.txt) |
| Sorbet | No errors; scope is `app/value_objects` | [Clean-checkout output](clean-checks.txt) |
| Live HTTP | Health 200; valid auth 200; missing auth 401; unknown route 404; malformed JSON 400 | [HTTP output](http-smoke.txt) |
| Rails autoloading | `bundle exec rails zeitwerk:check` passed | Native execution completed before commit `d443842` |
| Database isolation | Development `DB_DATABASE` and inherited `DATABASE_URL` resolve to `ledgerly_test` under test | Commands below |
| Database/production guards | Non-test name rejected during boot; `bin/ci` rejects production invocation | Commands below |
| Hosted CI | Successful RSpec, RuboCop and Sorbet run on Ubuntu x86_64 | [CI metadata](github-ci.json), [GitHub Actions run](https://github.com/amovingman/Ledgerly/actions/runs/44962119095) |

The hosted run emitted a checkout-action Node runtime deprecation annotation. The workflow subsequently pins the verified official `actions/checkout` v7.0.1 commit, which uses Node 24. Later workflow runs are available in GitHub Actions; the saved metadata identifies the original tested source commit.

Coverage applies to the small foundation codebase. It does not establish coverage of future billing or payment behavior, and there is no coverage threshold gate yet. Full model/service typing and coverage enforcement remain in Milestone 4.

## Reproduce the clean-checkout checks

Use Docker with Compose. Clone the repository into a new folder, copy `.env.example` to `.env`, and generate an API key as described in the root README. No Stripe credentials are needed for this milestone.

```sh
git clone https://github.com/amovingman/Ledgerly.git ledgerly-clean
cd ledgerly-clean
cp .env.example .env
# Set a freshly generated API_KEY in .env before continuing.
docker compose build api
docker compose up --no-build -d --wait
docker compose ps -a
docker compose exec api bin/smoke
docker compose run --rm -e RAILS_ENV=test -e TEST_DB_DATABASE=ledgerly_test -e REDIS_URL=redis://redis:6379/1 api bin/ci
```

For the recorded local clean-checkout run, the clone was under ignored `.tooling/clean-checkout`, Compose used project name `ledgerly-clean`, and the host API port was 3001 to keep it separate from the development stack. The ignored root `.env` was supplied explicitly via `--env-file`; application code and dependency configuration came exclusively from the clean clone.

To retain a Docker-generated coverage report, give the check container a name instead of `--rm`, then use `docker cp <container>:/rails/coverage app/` before removing the exited check container. The recorded clean-checkout report was copied into the workspace's ignored `app/coverage/` directory.

## Database safety checks

From `app/` with the pinned Ruby and installed gems:

```sh
RAILS_ENV=test DB_DATABASE=ledgerly_development DATABASE_URL=postgresql://invalid.example/ledgerly_production bundle exec rails runner 'puts ActiveRecord::Base.connection_db_config.database'
# Passed: prints ledgerly_test, without connecting to invalid.example.

RAILS_ENV=test TEST_DB_DATABASE=ledgerly_development bundle exec rails runner 'puts "guard bypassed"'
# Passed: nonzero exit; Test database name must end in _test or _test_<number>.

RAILS_ENV=production bin/ci
# Passed: nonzero exit; Refusing to run checks from a production environment.
```

The test suite also exercises invalid/missing/blank API credentials, malformed request bodies, pagination validation, missing/invalid resources, and dependency failure responses. Its readiness checks use real PostgreSQL and Redis connections for the healthy case.
