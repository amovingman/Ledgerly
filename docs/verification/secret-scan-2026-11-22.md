# Sensitive-information review — 2026-11-22

Project reference: [ROADMAP.md](../../ROADMAP.md). Reviewed commit `f4209c9f2e6eb8fbb937876362fdf24502d2bd2c` and the current working files, including the README refresh before its publication. The initial review printed no credentials, uploaded nothing to an external scanner and made no credential changes. The subsequent user-authorized local cleanup is recorded below. During the review and cleanup, no credentials were rotated, and no Git history or repository settings were changed.

## Result

**No genuine authentication credentials or private keys were detected in the versioned code, reachable history or inspected archives.** The initial local scan found seven task-generated secret copies; an expanded cleanup scan found one additional Stripe CLI configuration. All seven obsolete files have now been removed, and the active listener log has been redacted in place. The retained private `.env` is unchanged. Personal information remains in Git authorship metadata, and saved evidence contains sandbox resource identifiers.

| Item | Finding |
| --- | --- |
| Current project files | Scanned 897 versioned/current files, excluding ignored runtime tooling and reference repositories |
| Git history | Scanned all 13 reachable commits and examined 1,025 unique historical blobs |
| Compressed evidence | Inspected gzip/tar/ZIP content recursively; 52 archive containers and 1,576 members across current files and history |
| Known private values | No matches for configured API/Stripe secrets, non-default database credentials, or locally generated Rails secrets in scanned source/history/archive content; raw and selected encoded forms checked |
| Maintained scanner | Official Gitleaks v8.30.1 binary verified against its release checksum; default rules, full redaction, archive/decode traversal and inline allow-comment bypass disabled |
| Scanner candidates | 70 current-file matches and 70 history matches, all `generic-api-key`; every candidate verified as a SHA-256 digest rather than a credential |
| Local `.env` | Contains actual local credentials; ignored by Git, untracked and mode `0600` |
| Rails local files | Encrypted credentials and the development local-secret file are ignored/untracked; no master key is tracked. Parent-directory permissions block other-user traversal of this workspace |
| Repository visibility at initial review | Private; subsequent public publication was explicitly authorized by the user |
| GitHub secret alerts at initial review | Secret scanning was disabled; no GitHub alert-based assurance is claimed |

The two scanner reports contain duplicate findings across scan scopes. Of their 140 total entries, 134 matched hashes of actual scanned file/archive content. The remaining six matched the hash of the local **encrypted credentials file**, recorded in image-source manifests. A checksum of encrypted content is not the encryption key. No broad ignore rule or scanner allowlist was added to suppress these matches.

## Sensitive local copies outside Git

Before cleanup, an additional exact-value check of 1,410 ignored task-generated text files found current API/Stripe secrets in these seven files. All were Git-ignored and untracked:

| File | Sensitive value types |
| --- | --- |
| `.tooling/m2-verify.env` | Application API key |
| `.tooling/m2-sandbox.env` | Application API key, Stripe secret key and webhook signing secret |
| `.tooling/m4/stripe-listener.log` | Webhook signing secret |
| `.tooling/stripe/listen-main.log` | Webhook signing secret |
| `.tooling/stripe/sandbox.json` | Stripe secret key |
| `.tooling/stripe/listen.log` | Webhook signing secret |
| `.tooling/stripe/sandbox-create.log` | Stripe secret key |

These are **real sensitive local artifacts**, not checksum false positives. They were not part of the versioned snapshot, and their current secret values were not found in scanned Git history. Dependency caches, Docker authentication configuration and the audit's own output were excluded from this supplementary local-artifact pass.

## Authorized local cleanup

The user then requested removal of extra secret copies while preserving `.env` and the running app. The expanded scan included dependency caches, Docker configuration and audit output, uncovering one additional copy in Stripe CLI's local sandbox configuration.

| File | Action |
| --- | --- |
| `.tooling/m2-verify.env` | Deleted obsolete verification configuration |
| `.tooling/m2-sandbox.env` | Deleted obsolete sandbox configuration |
| `.tooling/m4/stripe-listener.log` | Deleted obsolete listener log |
| `.tooling/stripe/sandbox.json` | Deleted obsolete sandbox creation response |
| `.tooling/stripe/listen.log` | Deleted obsolete listener log |
| `.tooling/stripe/sandbox-create.log` | Deleted obsolete sandbox creation log |
| `.tooling/stripe/config.toml` | Deleted obsolete CLI sandbox configuration, including its duplicate API key and claim URL |
| `.tooling/stripe/listen-main.log` | Redacted 22 signing-secret occurrences in place, using equal-length overwrites to preserve the running listener's file descriptor and offset |

Validation after cleanup:

- Root `.env` is byte-identical to its pre-cleanup SHA-256 fingerprint, still mode `0600`, ignored and untracked. No backup containing its plaintext values was created.
- A scan of **18,125 regular `.tooling` files** (780,110,879 file bytes), including dependency caches and audit output, found **zero remaining matches for configured private values** in raw, base64 or URL-encoded form. Local Rails secrets were also checked as raw bytes. Nested gzip/tar/ZIP traversal inspected 590 distinct archive containers and 11,633 members; there were no read/archive errors and no symlinks were followed. These counts include local audit artifacts and do not imply the entire workspace is safe to publish.
- `/ready`, authenticated `/api/v1/status`, authenticated `/api/v1/customers` and `/dashboard/login` returned HTTP 200. PostgreSQL and Redis readiness passed; all five main Compose services remained running and healthy.
- The real `bin/smoke` job passed Rails → Redis → Sidekiq → PostgreSQL → Redis. The original Stripe listener stayed running with its log open; it was not restarted.
- Financial counts were unchanged: 3 customers, 3 usage events, 3 invoices, 24 ledger entries, 12 webhook receipts, 12 journals, 3 payments and 6 refunds. All eight accounting checks reported zero violations.

The archived `docs/verification/milestone-2/redis-interruption.py` still references its original isolated-stack `.tooling/m2-verify.env`; historical evidence was preserved rather than redirecting that destructive outage helper to the main `.env`. Reproducing that old experiment requires recreating its isolated configuration. Standalone Stripe CLI use now requires credentials supplied from the retained private `.env` or a fresh login; the currently running listener is unaffected. A future listener startup may emit its signing secret again, so generated CLI logs should remain private.

Sanitized cleanup receipts and scan results are stored under ignored `.tooling/security-audit/`. No application source, benchmark evidence, Git history, credentials in `.env`, or repository settings were changed, and nothing was committed or pushed during the cleanup.

## Information that is present

1. **Personal author email:** all 13 commits use a personal Gmail address in author/committer metadata. The address is deliberately not repeated here. Repository readers can access it through Git history. A GitHub-provided no-reply address can be used for future commits if email privacy is desired; that would not change existing history.
2. **Sandbox identifiers and sample billing records:** reports and dashboard screenshots contain Stripe test account/customer/invoice/event references and test-mode amounts. These references do not authenticate requests, but identify test resources. Example customer emails use reserved test domains.
3. **Development configuration:** Docker/CI/benchmark configuration includes documented local or fixture passwords and keys. These are separate from the actual ignored API/Stripe credentials. Evidence also includes local workspace paths and runtime details.

Representative customer and sign-in screenshots were inspected visually: they show synthetic test details and an empty password field, rather than a visible access key. This was not an exhaustive OCR scan of every historical image.

## Method and scope

- Refreshed remote refs/tags before reviewing reachable history.
- Ran Gitleaks against full Git history and an isolated snapshot of tracked/current project files, with secrets redacted in its private reports.
- Independently traversed historical blobs and nested archives, comparing known configured private values and inspecting URL/claim-link candidates.
- Reviewed email-pattern candidates. Apparent addresses in source/archive text were Ruby instance-variable expressions or generated RBI filenames; the real personal email finding is in Git commit metadata.
- Checked Git/Docker exclusions, parameter filtering and authenticated webhook metadata serializers. Raw Stripe webhook payloads remain stored in PostgreSQL and are excluded from dashboard/API receipt projections.

Detailed redacted scanner output and the local analysis are under ignored `.tooling/security-audit/`. The official scanner release is [Gitleaks v8.30.1](https://github.com/gitleaks/gitleaks/releases/tag/v8.30.1). This is a credential/privacy review, not a dependency-vulnerability assessment or production penetration test.

## Follow-up

- Completed: removed seven obsolete credential-bearing files and redacted the active listener log. Keep `.env` and future generated credential/log files private.
- Use a GitHub no-reply author email for future commits if the personal address should not be shared with repository readers.
- Enable repository secret scanning/push protection if available for this account and repository.
- The user subsequently authorized publishing the README, roadmap and this sanitized report, then making the repository public. Local `.env`, `.tooling` and unrelated runtime files are excluded. The original visibility/scanner observations above describe the initial review, rather than ongoing repository settings.

No confirmed credential exposure in reachable Git history was identified by these checks. Local plaintext copies identified above were removed or redacted during the authorized cleanup; required private configuration remains in `.env`. Application source, existing benchmark evidence and commit history were left intact.
