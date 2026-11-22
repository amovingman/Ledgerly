# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

The project owner and reviewers inspect the Ledgerly billing API through a read-only dashboard. Reviewer/demo use is inferred from the portfolio goal and the accepted dashboard proposal; no separate customer login or tenant roles are specified.

## Product Purpose

Record metered usage, issue invoices atomically, and reconcile Stripe test-mode webhook effects without duplicating financial journals. The dashboard makes those existing records inspectable without billing mutations.

## Operating Context

The source of truth is ROADMAP.md. Rails 8.1/PostgreSQL/Sidekiq/Redis already exist in app/. Browser views are a new Milestone 5 surface inside that application. Existing API clients continue using Bearer authentication. Local test-mode data and real saved verification evidence exist; a synthetic demo is not assumed to be real customer activity.

## Capabilities and Constraints

The user explicitly requested customers, usage, invoices, ledger entries and webhook status. Search, bounded pagination, read-only drill-downs and freshness support that inspection. No create, collect, refund, replay, cancel or edit controls belong in the dashboard. Keep integer money exact and currencies separate. API credentials must not enter bundles, URLs or browser storage. The user authorized committing and pushing all outstanding project changes after finishing dashboard acceptance.

## Brand Commitments

Name: Ledgerly. No existing visual implementation or binding visual brand was found. Voice is factual, direct and specific to billing operations.

## Evidence on Hand

PostgreSQL-backed customer/usage/invoice/journal/webhook records; signed replay, sandbox and performance reports under docs/. Historical reports retain their source/resource scopes. New views must compute totals from current data and show honest zeros/empty states. There are no testimonials, production-traffic claims or customer logos to invent.

## Product Principles

- A financial figure is traceable to its underlying records.
- A read-only session never authorizes a billing mutation.
- Counts, states and freshness describe observed data.
- PostgreSQL remains authoritative; the UI does not manufacture payment success.
