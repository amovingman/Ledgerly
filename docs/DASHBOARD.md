# Read-only dashboard

[ROADMAP.md](../ROADMAP.md), Milestone 5, records implementation, completed local acceptance and publishing status. The dashboard runs inside the Rails API application; it needs no Node server, npm install or separate frontend deployment.

## Open it

Start the existing stack using the README instructions, rebuilding the API image after source changes:

```sh
docker compose build api
docker compose up --no-build -d --wait
```

Open [the local dashboard](http://127.0.0.1:3000/dashboard). Sign in with this instance's `API_KEY` from the local `.env`. The browser submits it once to the same-origin server. It is not included in a bundle, URL, localStorage or sessionStorage. Never publish `.env` or put a real key in a screenshot. Sign-in requires configured access; an unset key fails closed. `DASHBOARD_DATA_LABEL` can change the workspace label; Compose's default is “Local test workspace.”

The primary source is the existing development PostgreSQL database. No demo seed or reset is required. A new empty installation shows honest empty states. Current screenshots show sandbox verification records, not production customers or the separate 50k benchmark dataset.

## Views and inspection path

| View | What it reads |
| --- | --- |
| Overview | Actual counts, six newest ledger entries, lifetime debit/credit totals by currency, three recent records in each activity area |
| Customers | Name, email, Stripe customer reference, creation date; detail shows per-currency receivables and scoped usage/invoice/ledger links |
| Usage | Metric, integer quantity, customer, UTC occurrence, billed state and linked invoice |
| Invoices | Customer, UTC billing period, issued amount/currency, current state; detail shows up to 100 line items and the newest 25 journal entries |
| Ledger entries | Account, journal identity/type, source invoice, exact debit/credit/currency and recorded time |
| Webhooks | Stripe event identity/type, status, attempts and received time; detail adds dispatch/completion/attempt times, recorded error and event-linked journal entries |

Open a customer → View usage → linked invoice → View all journal entries. Alternatively, open a webhook → inspect its processing timeline and related journal rows. A replay/ignored/review receipt may have no postings; logical payment identity remains distinct from webhook delivery identity.

Lists default to 25 records, with a hard maximum of 100. Search, supported status filters and pagination are server-backed. Customer and invoice/event scopes survive pagination and can be cleared. The browser hash preserves each view for back/forward navigation. Manual Refresh reads current data; a failed refresh retains previously loaded rows and labels the failure. No polling loop is added.

Money and quantities arrive as decimal strings. Money uses JavaScript `BigInt` cents, including values above `Number.MAX_SAFE_INTEGER`; currencies are never summed together. Negative receivables indicate a credit. Overview debit/credit differences are aggregate differences, not a substitute for the per-journal accounting audit. Billing-period ends are exclusive. List times and dates use UTC.

## Authentication and write boundary

- The encrypted, HttpOnly, SameSite Strict cookie expires after 30 minutes. Production cookies require HTTPS. Configure the normal Rails `SECRET_KEY_BASE` consistently when running multiple instances; development image rebuilds may invalidate local sessions.
- Cookies contain a key fingerprint and expiry, rather than the API key. Rotating `API_KEY` invalidates existing viewer sessions. A copied encrypted cookie remains a credential until expiry/key rotation; sign-out clears the current browser session, not a central revocation list.
- CSRF/origin protection applies to sign-in and sign-out. Expired/invalid forms render a recoverable sign-in page. Sign-out uses explicit POST `/dashboard/logout`; API mode omits the HTML method-override middleware. DELETE `/dashboard/session` is also supported directly.
- Ten sign-in attempts per three minutes are allowed per IP using the configured Rails cache. The local memory cache is process-local; this is an owner-operated test workspace, not a multi-tenant identity system.
- Data endpoints require the viewer session and accept GET only. A dashboard cookie does not authorize existing Bearer API endpoints. There are no collect, refund, replay, create, edit or cancellation controls.
- HTML/JSON responses use `Cache-Control: no-store`, a restrictive same-origin CSP and frame denial. Public code/font assets revalidate with `no-cache`; initial versioned asset URLs avoid stale heuristic browser caches. Webhook raw payloads are excluded. Server-provided text is escaped before rendering.

Dashboard JSON routes live under `/dashboard/data/{overview,customers,usage,invoices,ledger,webhooks}`; details are `/customers/:id`, `/invoices/:id` and `/webhooks/:id` under that prefix. Internal projections are separate from the established API contract in [API.md](API.md). These reads issue no billing writes or outgoing Stripe requests. A customer-balance read can fill the existing Redis read cache.

## Checks and limits

Run the existing `app/bin/ci` against isolated PostgreSQL/Redis test services. The suite includes 16 dashboard request examples covering auth, exact totals, scope isolation, invalid filters, CSRF and the real sign-out form. Run the dependency-free frontend checks from the repository root:

```sh
node --test scripts/test_dashboard.mjs
```

GitHub Actions includes those Node tests; release publication and hosted results are tracked in the roadmap. No package dependencies were added. Fonts are self-hosted with their OFL licenses. [DESIGN.md](../DESIGN.md) describes the implemented system.

[Milestone 5 evidence](verification/milestone-5/README.md) records passed functional and visual acceptance, with the original failed evidence retained. Dashboard endpoints have not been included in the historical throughput/latency measurements. Overview aggregates and substring searches can scan substantial data even though returned lists are bounded; this milestone adds no new performance claim.
