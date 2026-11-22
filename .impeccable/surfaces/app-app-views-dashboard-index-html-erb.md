---
version: 1
slug: "app-app-views-dashboard-index-html-erb"
primary_target: "app/app/views/dashboard/index.html.erb"
related_targets: ["app/public/dashboard-assets/dashboard.css","app/public/dashboard-assets/dashboard.mjs"]
---

# Ledgerly dashboard

Mode: Operate. Milestone 5 in ROADMAP.md is authoritative. User confirmed existing local data and a visual-mockup-first workflow. Approved comp: docs/verification/milestone-5/approved-mockup.png (A).

Audience/job: owner or reviewer traces usage → invoice → double-entry rows and inspects webhook processing. All data comes from bounded PostgreSQL-backed reads; no billing mutations or invented totals.

## Direction contract

THESIS: Ledgerly is an inspection desk, organized around the bank statement's aligned evidence rather than a marketing hero. The seven grounded structures considered were a reconciliation desk, customer case file, period-close report, statement inspection book, distributed trace, operations queue and audit notebook. The assigned fourth structure is the statement inspection book.

OWN-WORLD: low-chroma blue-grey ground, white reading surfaces, ink chrome, Geist text and Geist Mono IDs. Right-aligned money columns and one-pixel rules hold the hierarchy; blue marks the current ledger data only.

STORY: see actual totals, open a customer, follow its usage and invoices, inspect both sides of a journal, then inspect the posting event. Honest zeros and explicit statuses earn trust.

FIRST VIEWPORT: 256px quiet labelled navigation; fluid canvas with 24–32px margins; 24px noun title and manual refresh. A compact count strip leads to a debit/credit book, then paired recent invoice/webhook and customer/usage lists. All five requested areas are discoverable at desktop height 900px. Phone navigation folds and each table becomes readable record rows.

FORM: candidate 4, seed cd93f0e9. Taste sheet achromatic-ledger, seed 618227027. Its consumer net-worth/budget overview pattern is replaced on factual grounds: Ledgerly has no personal net worth, budgets or account-creation flow. Keep its open-plane shell/type/tonal discipline. Catalog challengers were considered as craft references; none outranks billing clarity. User approved A — Statement book, docs/verification/milestone-5/approved-mockup.png. Illustrative names/dates/rows in the mockup must be replaced with current PostgreSQL data; generated mockup financial row directions are not accounting authority.

SIGNATURE: an invoice's amount opens into actual line items and journal rows, preserving customer scope and currency. Keyboard, loading, empty, expired-session and error states are part of that path. Motion is limited to control feedback.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
