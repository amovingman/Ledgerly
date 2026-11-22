# Sorbet contracts and generated interfaces

[Milestone 4](../ROADMAP.md#milestone-4--quality-and-portfolio-release-week-4) expands the original pagination-only check. Run these commands from `app/` with the documented test database environment:

```sh
bin/typecheck
ruby script/typecheck_contracts.rb
bin/rbi --check
```

`bin/typecheck` checks all application definitions, with `typed: true` bodies on the core models and billing/Stripe services. `PaginationParams`, generic immutable `Billing::Result`, and billing/provider type aliases use `typed: strict`. Request controllers, job wrappers, retry-policy integration and response serializers remain gradual/dynamic boundaries; this is not a claim that every application method is statically typed.

The core contracts include usage validation, UTC periods, invoice issuance, generic record results, currency/amount balance rows, webhook receipt, payment snapshot shapes, reconciliation/posting, collection operations, recovery and cache invalidation. Optional associations remain nilable; assertions at persisted-record boundaries follow required foreign keys. Validation callbacks retain explicit guards for invalid/new records. Services accept raw request values where validation must still return normal API errors. The controller converts permitted Rails parameters to a symbol-keyed hash before usage ingestion.

Provider JSON, Redis-decoded JSON and injected provider adapters remain explicit `T.untyped` boundaries. Contract validators still verify test mode, currency, amounts, customer and effect identities before posting. Type signatures supplement PostgreSQL constraints, transactional locking and runtime tests; they do not replace financial validation. Checking is gradual: inferred dynamic values from framework calls can still propagate through a typed file. The probes protect selected concrete contracts, not a claim that every expression is statically resolved. Runtime signatures are enabled. Generic return types preserve `Invoice`, `UsageEvent` and `StripeEvent` at callers, rather than erasing them to a shared record type.

## Generation and drift checks

Tapioca **0.20.0** is pinned in `Gemfile.lock`. The [official Sorbet guidance](https://sorbet.org/docs/faq) points Rails users to [Tapioca](https://github.com/Shopify/tapioca). Committed generated RBIs describe gem interfaces and actual schema-derived columns, associations, relations, scopes and Sidekiq worker methods. Rails column RBIs use Tapioca's default **persisted** assumption: non-null database columns have non-nil getter types on valid stored records. Invalid/new records can still contain nil; validation behavior is tested at runtime. RBI files do not add runtime attributes or associations.

After changing dependencies, the schema or relevant DSLs, prepare the test database and regenerate:

```sh
RAILS_ENV=test bin/rails db:prepare
RAILS_ENV=test bin/rbi
bin/typecheck
RAILS_ENV=test bin/rbi --check
```

`--check` verifies gem version synchronization and compares schema/DSL output without changing files. CI runs it after database preparation. Regeneration intentionally uses one worker for reproducibility and resource bounds. Generated files are marked as generated for GitHub review. Use `bin/rbi` as the regeneration entry point.

Stripe 21.1.0's exported RBI graph refers to missing V2 `Amount` constants. `bin/rbi` therefore reflects that gem's actual loaded API **without merging its exported RBI files**, while retaining other gems' exported signatures. The application gateway has its own typed public request/response contract; SDK dispatch and JSON values stay dynamic. This scoped workaround is reproducible, not a global type-error suppression or a hand-invented definition of missing provider classes.

The type-contract probe compiles one valid client and three intentionally invalid clients. It must accept the valid program and reject a wrong generic result record, a wrong webhook record and string-method use on an integer. These checks ensure a future configuration change cannot silently reduce checking back to pagination alone.
