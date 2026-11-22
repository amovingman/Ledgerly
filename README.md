# Ledgerly

Ledgerly is a Rails API project for metered usage, invoicing, and reliable Stripe reconciliation. The application lives in `app/`; the existing reference repositories are separate from application code.

Work follows [ROADMAP.md](ROADMAP.md), the source of truth for milestones, acceptance checks, decisions, and measured evidence. Milestone 0 establishes the development foundation. Milestone 1 provides core billing models, idempotent usage ingestion, atomic invoicing, and ledger-derived balance endpoints; see [the core API reference](docs/API.md) and [billing rules](docs/BILLING_RULES.md) for implemented contracts. Stripe webhooks and collection remain in Milestone 2. No throughput or latency benchmark has been achieved.

## Foundation stack

| Component | Version / purpose |
| --- | --- |
| Ruby | 3.4.13, recorded in `app/.ruby-version` |
| Rails | 8.1.4.1, API mode |
| Bundler | 4.1.0; dependency versions are committed in `app/Gemfile.lock` |
| PostgreSQL | 17.12 container; authoritative application database |
| Redis | 8.2.3 container; Sidekiq queue and foundation smoke-test coordination |
| Background jobs | Sidekiq, concurrency 5 |
| Quality checks | RSpec, SimpleCov, RuboCop, Sorbet |

The roadmap records the change from the original Rails 7 proposal. The Docker image is for development and testing; production deployment is outside this milestone.

## Start with Docker Compose

Install Docker with Compose, then run these commands from the repository root:

```sh
cp .env.example .env
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
```

Replace the blank `API_KEY=` value in `.env` with the generated value. If Ruby is unavailable on the host, generate a random key with your password manager. `.env` is ignored by Git; the example contains no application API key.

```sh
docker compose build api
docker compose up --no-build -d --wait
docker compose ps -a
curl --fail http://127.0.0.1:3000/up
curl --fail http://127.0.0.1:3000/ready
docker compose exec api bin/smoke
```

Compose loads the root `.env` automatically. The `setup` service prepares the development database and exits successfully; this is expected. The API and worker start after setup completes. PostgreSQL and Redis have no published host ports; the API binds to `127.0.0.1:3000` by default. Set `PORT` in `.env` to change the host port.

The smoke script verifies database connectivity, enqueues `FoundationSmokeJob`, and waits for the worker's result in a unique Redis key that expires after 60 seconds. It checks actual background-job execution in addition to API readiness.

```sh
docker compose logs --tail=100 api sidekiq setup
docker compose run --rm -e RAILS_ENV=test -e TEST_DB_DATABASE=ledgerly_test -e REDIS_URL=redis://redis:6379/1 api bin/ci
docker compose down
```

Database and Redis volumes survive `docker compose down`. The image contains a copy of the source; there is no source bind mount. Rebuild with `docker compose build api`, then run `docker compose up --no-build -d --wait` after code or dependency changes. All application services share the image built by the API service. Standalone `docker-compose` can replace `docker compose` if that is how Compose is installed locally.

## Run natively

Use Ruby 3.4.13 and Bundler 4.1.0 with a running PostgreSQL 17 server and a compatible Redis server. Add the selected Ruby's `bin` directory to `PATH` before using `ruby`, `gem`, or `bundle`. On macOS, a Homebrew PostgreSQL installation may also require its `bin` directory on `PATH` when compiling the `pg` gem.

Create `.env` and set `API_KEY` as described above. Adjust `DB_USERNAME`, `DB_PASSWORD`, `DB_HOST`, and `DB_PORT` for an existing local PostgreSQL role that can create the development and test databases. The example role `ledgerly` is created by the PostgreSQL container; native installations must supply their own role or create it explicitly.

Rails does not automatically load the root `.env` in native mode. Export it in each terminal before starting application commands:

```sh
# From the repository root:
set -a
source .env
set +a
cd app
gem install bundler --version 4.1.0
bundle install
bin/setup --skip-server
bin/rails server -b 127.0.0.1
```

`bin/setup --skip-server` installs missing gems and prepares both development and test databases without launching the server. In a second terminal, load the same environment and run the worker:

```sh
set -a
source .env
set +a
cd app
bundle exec sidekiq -C config/sidekiq.yml
```

With the API and worker running, execute `bin/smoke` from `app/` in another terminal with the same exported environment. Native Redis defaults to database 0 for development; use database 1 for tests. These are logical namespaces, so use an isolated Redis instance when testing alongside other applications.

## API foundation

All responses use JSON. Core business routes and examples are documented in [docs/API.md](docs/API.md).

| Request | Authentication | Response |
| --- | --- | --- |
| `GET /up` | Public | `200` with `{"status":"ok"}` when the application is live |
| `GET /ready` | Public | `200` when PostgreSQL and Redis are available; otherwise `503` |
| `GET /api/v1/status` | `Authorization: Bearer <API_KEY>` | `200` with `{"data":{"service":"ledgerly","status":"ok"}}` |

Readiness returns `{"status":"ok","checks":{"postgres":"ok","redis":"ok"}}`. Unavailable dependencies use `"unavailable"` in their check and the overall status; internal exception details are not exposed.

Missing, incorrect, or malformed authentication returns `401`. An empty or missing configured `API_KEY` fails closed with `503`. Future Stripe webhook endpoints will verify Stripe signatures separately from API-key authentication.

Errors have the shape `{"error":{"code":"...","message":"..."}}`:

| Condition | HTTP status | Code |
| --- | --- | --- |
| Malformed JSON | 400 | `invalid_json` |
| Missing or invalid request parameters | 400 | `bad_request` |
| Unknown route with valid authentication | 404 | `not_found` |
| Active Record validation failure | 422 | `validation_failed` |

List endpoints default to `page=1&per_page=25`, allow at most 100 records per page, and require strictly positive integer parameters.

## Checks and CI

Run the complete local check from `app/` with the exported native environment:

```sh
RAILS_ENV=test TEST_DB_DATABASE=ledgerly_test REDIS_URL=redis://127.0.0.1:6379/1 bin/ci
```

Test database configuration ignores inherited `DB_DATABASE` and `DATABASE_URL` values. It defaults to `ledgerly_test`; use `TEST_DB_DATABASE` or an explicit `TEST_DATABASE_URL` to override it. The resolved test database name must end in `_test` or `_test_<digits>`, so an accidental development database selection aborts before tests run. Database host and credentials still come from the shared `DB_*` settings unless the test URL overrides them. Use a dedicated test database and Redis namespace.

The check prepares the test database and runs RSpec, RuboCop, and Sorbet. The initial Sorbet check covers `app/value_objects`; model and billing-service typing expands in Milestone 4. RSpec starts SimpleCov before loading Rails and writes its report to `app/coverage/index.html`. Coverage figures are meaningful only for the files and scenarios present in that run; the roadmap's later coverage target is not a completed project result.

GitHub Actions runs on pushes and pull requests using the pinned Ruby version, locked dependencies, PostgreSQL and Redis services, and the same quality checks. See [.github/workflows/ci.yml](.github/workflows/ci.yml). Actual verification results and any remaining limitations are recorded in the [roadmap work log](ROADMAP.md#work-log).

Milestone 1 verification, including live HTTP concurrency, is saved in [docs/verification/milestone-1/README.md](docs/verification/milestone-1/README.md). The next milestone adds Stripe collection, webhook reconciliation, and failure recovery while preserving the billing and idempotency rules in [ROADMAP.md](ROADMAP.md#billing-and-reliability-rules).
