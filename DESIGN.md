---
name: Ledgerly
description: A quiet inspection desk for recorded billing activity.
colors:
  ground: "#f2f4f7"
  surface: "#fff"
  ink: "#141414"
  muted: "#60646c"
  line: "#e4e7eb"
  rule: "#eef0f3"
  control: "#c5cad2"
  active: "#e5e8ed"
  blue: "#1d5fbf"
  nav-selected-bg: "#dfeafb"
  nav-selected-ink: "#164eab"
  book-ground: "#f5f8fc"
  totals-ground: "#e9eef4"
  positive-ink: "#235a38"
  positive-bg: "#ecf4ee"
  negative-ink: "#982e30"
  negative-bg: "#fcefee"
  warning-ink: "#86531a"
  warning-bg: "#faf1e3"
  neutral-ink: "#555d67"
typography:
  headline:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "32px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.025em"
  title:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 700
    lineHeight: 1.4
  overview-title:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 700
    lineHeight: "24px"
  navigation:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
  count:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "26px"
    fontWeight: 700
    lineHeight: 1.1
  count-label:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
  body:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
  record:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Geist, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 400
  mono:
    fontFamily: "Geist Mono, monospace"
    fontSize: "12px"
    fontWeight: 400
rounded:
  status: "4px"
  control: "6px"
  panel: "8px"
spacing:
  tight: "4px"
  inline: "8px"
  gap: "12px"
  mobile-inset: "16px"
  panel-inset: "20px"
  canvas-inset: "24px"
  overview-gap: "18px"
components:
  button:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "8px 12px"
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.surface}"
    rounded: "{rounded.control}"
    padding: "8px 12px"
  input-search:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "0 12px 0 36px"
    height: "38px"
  button-refresh:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "8px 12px"
    width: "108px"
  nav-selected:
    backgroundColor: "{colors.nav-selected-bg}"
    textColor: "{colors.nav-selected-ink}"
    typography: "{typography.navigation}"
    rounded: "{rounded.control}"
    padding: "8px 12px"
  status-positive:
    backgroundColor: "{colors.positive-bg}"
    textColor: "{colors.positive-ink}"
    rounded: "{rounded.status}"
    padding: "2px 6px"
  panel:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.panel}"
---

# Design System: Ledgerly

## Overview

**Creative North Star: "Statement book"**

Quiet, cool surfaces hold a dense but readable record of billing activity. Aligned figures, restrained rules and direct labels provide the hierarchy; the blue three-line mark gives the application a small, recognizable signature. This documents the implemented dashboard, not the illustrative records in the approved mockup.

**Key Characteristics:**

- Cool ground and white reading panels.
- Strong Geist headings, compact records and monospaced identifiers.
- Exact amounts, explicit currencies and traceable record links.
- Small corners, fine rules and minimal motion.

The implementation lives in `app/public/dashboard-assets/` and `app/app/views/dashboard/`. The compact overview is isolated in the dependency-free `overview.mjs` module and re-exported by `views.mjs`. [ROADMAP.md](ROADMAP.md) owns Milestone 5 status and acceptance evidence; [PRODUCT.md](PRODUCT.md) owns product constraints. This file describes design behavior rather than certifying acceptance.

## Colors

Blue is the primary accent against a cool neutral ground. `blue` marks the logo, focus rings, nonzero entry amounts and ledger footer figures; selected navigation uses its lighter dedicated pair. `ink` carries headings and the sign-in action. `muted` carries metadata and zeros. `line` separates panels and larger groups; `rule` separates record rows; `control` outlines fields and buttons. The `active` custom property exists in the stylesheet but is not currently assigned to a component.

Status colors always accompany visible words and a small dot: green for paid/processed/billed, red for dead/payment failed, amber for review/received/unbilled, neutral for other states. The pale `totals-ground` groups per-currency lifetime totals in the ledger table footer. The earlier `book-ground` remains in the stylesheet for the legacy book table; the overview no longer renders that separate table. Do not treat a color or decorative dot as financial evidence.

## Typography

Geist is used throughout, with locally served 400, 500 and 700 faces; Geist Mono 400 distinguishes record and remote identifiers. Fonts ship with their OFL notices. The system fallback stacks are normative above. Headings use Geist, not a condensed display family.

- Page headings: 32px / 700 / 1.2, with −0.025em tracking; 26px at widths up to 700px.
- Panel headings: 17px / 700 / 1.4; overview panel headings: 18px / 700 / 24px.
- Base text: 14px / 400; table records: 13px / 1.5; metadata: usually 11–12px.
- Overview counts: 26px / 700 / 1.1, with 14px labels reducing to 12px on phones. Detail totals: 28px / 500, reducing to 26px on phones.
- Sidebar navigation: 16px with 18px icons; selected text uses weight 500. The desktop brand is 24px / 700 with −0.02em tracking.
- The sign-in heading is 28px / 1.25 on desktop and 30px on phones.

Money and numeric columns use tabular numerals. `format.mjs` formats integer values with `BigInt`, including the two decimal places, rather than converting money to floating point. Keep currency labels explicit and totals separate by currency. Dates and times use UTC.

## Layout

Desktop uses a fixed 256px sidebar and a fluid main area with 20px vertical and 24px horizontal padding. At 1600px and wider, horizontal canvas padding becomes 48px. The overview uses a five-column count strip, a full-width ledger book and two equal recent-record columns with an 18px gap. Detail pages use a flexible reading column plus a 300px record panel.

At 1100px and below, a 54px top bar replaces persistent navigation; the 256px sidebar slides beneath it, and the main area loses its left margin. Detail metadata narrows to 280px. At 700px and below, the canvas uses 16px side insets, overview counts use two columns, reading panels and details stack, and list tables become two-column labelled records. The first record cell spans both columns; long IDs wrap. The ledger preview and all four recent panels use the same labelled-record treatment, with full customer names wrapping. Ledger footer totals stack with explicit currency, total debits, total credits and difference labels; both sides of each entry stay visible. The overview gap reduces to 12px.

Desktop panels normally use 20px side insets; compact overview panels use 16px, while the ledger preview retains 20px. Phone panels use 16px. Standard table records use 14px vertical padding; compact overview tables use 5px row padding and 6px header padding, with 19px ledger and 20px recent-record line heights. Phone records use 14px vertical padding and 40px minimum main/pagination controls.

The desktop sidebar has 44px bottom padding. A fine top rule separates its labelled read-only information and sign-out controls. Refresh sits to the left of the full UTC read timestamp. The additional page footer remains on collection and detail views; the overview alone hides it because its tables already label currency and UTC times. This scoped rule uses `:has()` in the supported browser target.

## Elevation & Depth

The dashboard has no box shadows. White panels, cool ground and one-pixel borders establish depth. Navigation overlays use a `#14141433` scrim. Focus uses a 2px blue outline with a 3px offset, rather than elevation. Buttons transition background and border over 150ms; the navigation drawer moves over 180ms. Reduced-motion preference removes transitions and animations.

## Shapes

Panels use an 8px radius, controls and navigation use 6px, and status labels use 4px. Dots alone are circular. One-pixel rules and simple stroke icons maintain a restrained form language. The brand asset is a local vector of three offset blue horizontal lines; no raster imagery ships with this dashboard.

## Components

### Buttons and fields

White outlined buttons support refresh, pagination and navigation. The desktop refresh control is 108px wide with 14px text; on phones it becomes a 40px icon button with an accessible name. The sign-in action uses ink with white text. Default buttons have a 36px minimum height, 8px × 12px padding and a 6px radius. Hover darkens the border and changes the ground; disabled controls dim to 60%. Search fields are 38px high, increasing to 42px on phones, with room for a 16px search icon. Labels remain available to assistive technology.

### Navigation and status

Navigation rows are at least 40px high with 18px stroke icons and 16px labels. Selection uses the pale blue pair and `aria-current="page"`. On smaller screens, opening the drawer makes main content inert, focuses navigation and contains keyboard traversal. Escape closes it and restores the menu button focus; the closed sidebar is inert. The sidebar footer pairs an information icon with “Read-only workspace” and a sign-out icon with its visible action label. Status chips are compact, labelled state reports, not actions.

### Reading panels and records

White, bordered panels hold tables, key/value records, empty messages and the processing timeline. Tables retain captions and header semantics. The overview ledger has Entry, Timestamp (UTC), Description, Currency, Debits, Credits and Difference columns; each entry difference is debit minus credit. Its `tfoot` holds lifetime totals separated by currency, rather than summing the six-entry preview. The four recent panels are compact semantic tables. Customer names truncate on desktop with a title and a link to their complete record, then wrap on phones. Latest usage shows Event, Customer, Metric and Quantity; occurrence timestamps remain in the scoped usage list. Links lead from customers to scoped usage/invoices/ledger, from invoices to line items and journal rows, and from webhook receipts to processing timestamps and related postings. Raw webhook payloads are excluded. Keep zeros visible and preserve half-open billing-period wording.

### Loading, error and freshness

Loading uses plain status text and `aria-busy`; empty states state which records are absent. A failed refresh preserves the previous records and explicitly identifies them as previously loaded. Errors offer a retry action. Successful reads update the complete “Read at YYYY-MM-DD HH:MM:SS UTC” freshness label, which is hidden on phones. Search waits 350ms before updating the route, and filters reset pagination. Expired sessions clear displayed records and return to server-rendered sign-in.

### Access boundary

The server establishes the authenticated browser session; application bundles contain no access key. The dashboard reads existing local PostgreSQL-backed data. Sign-in/out are session actions; billing creation, collection, refunds, replay and edits have no dashboard controls. Do not imply that a viewing session authorizes API writes.

## Do's and Don'ts

### Do:

- **Do** preserve exact integer amounts, original currencies and UTC labels.
- **Do** retain compact desktop alignment and labelled mobile records.
- **Do** keep the blue mark, Geist hierarchy and visible keyboard focus consistent.
- **Do** describe actual records, zeros, failures and read freshness plainly.

### Don't:

- **Don't** mix currencies or round financial values through JavaScript Number.
- **Don't** copy mockup names, figures or accounting directions into live records.
- **Don't** add billing mutation controls to this read-only surface.
- **Don't** replace reading panels with decorative charts, raster backgrounds or shadow effects.
