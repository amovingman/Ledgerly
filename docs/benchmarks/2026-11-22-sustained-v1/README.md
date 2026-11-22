# Sustained signed-webhook throughput, 2026-11-22

This follow-up to [Milestone 3](../../../ROADMAP.md) tests current release `c9ed621c77b2384d056c69cf17dde86be739c81c` before optimization. **The throughput criterion was met on four vCPUs: 5,381–5,418 unique completions in every complete minute of a seven-minute run.** The full conservative gate remains **failed** because sampled pending work peaked at 349 against a predeclared limit of 100. Zero HTTP failures/client drops, all accepted work drained, no ending backlog, zero measured post-first-minute queue growth, and accounting checks passed. The longer two-vCPU run failed throughput; this is not a reliable two-vCPU capacity claim. Earlier baseline and optimized evidence directories remain unchanged.

The workload offers 100 signed deliveries/second. Ten percent repeat an event ID; another ten percent use distinct event IDs for the same payment. Thus the maximum is 5,400 distinct processed events and 4,800 new payment effects per minute, rather than 6,000 payments/minute. The host client uses 64 threads and a bounded 256-request capacity; the historical one-minute client used 32/64. Both current before/after runs use the same new client.

The ordinary mixed fixture has only 10,000 unpaid invoices. A separately prepared all-unpaid variant retains the same 50,000 invoice/usage/issuance identities, starts with 50,000 issuance journals/100,000 rows and no payments/refunds/events, and resets invoice status/read versions. The workload excludes 5,000 canonical refund cases and shuffles the remaining invoice IDs with seed 20261121. Each run warms 100 reserved fresh payments before timing, then uses separate fresh identities. This is not the original mixed-fixture experiment.

Only the isolated benchmark environment is reset. The read-only local provider, pinned real Stripe SDK, fixed 2 ms minimum delay/provider request, original integrity constraints, database, recovery and resource caps remain enabled. No external Stripe load or outgoing charges are generated. Initial experiments used a 2-vCPU Docker VM shared with the idle development stack; the final experiment temporarily used 4 vCPUs with the same configured 4 GiB memory. This additional resource allocation is reported separately. API and worker each have 1 CPU/512 MiB caps; PostgreSQL 1 CPU/768 MiB, provider 0.5 CPU/128 MiB, Redis 0.5 CPU/128 MiB, recovery 0.5 CPU/256 MiB. Initial Sidekiq concurrency/database pool is five.

The pass criteria were set before results: at least five minutes, >=5,000 unique completions in every complete minute, no HTTP failures or client capacity drops, all accepted events drained, expected unique payment effects, eight accounting checks clean, no retry/dead/review work, and bounded backlog (sampled peak <=100; ending <=25; post-first-minute growth <=0.1 event/second). Five-second queue samples are observations, not an exact instantaneous maximum. Queue trend is the endpoint slope between the first and last samples after the first minute, rather than a regression across samples. Complete-minute counts use stored PostgreSQL completion timestamps and the minimum-round-trip server clock calibration, and exclude drain completions. End-of-offering and final-drain counts are retained separately.

An initial run is retained as an interrupted monitoring trial: the final read reused a connection idle for five minutes and received `RemoteDisconnected`. Its raw requests survive, but it is not a valid completed experiment. The corrected monitor opens fresh observation connections, checkpoints its boundaries/HTTP/end/drain snapshots, and never retries measured webhook requests.

The first optimized preflight also caught Python 3.9 rejecting a PostgreSQL timestamp with five fractional digits. No timed offering started in that attempt. Parsing now accepts zero through six digits, checked against fixed timestamps; the warm-up state was reset before the timed repeat. Both preflight failures are retained.

## Profile and changes

Sequential diagnostics process 200 fresh payments through the real SDK/local HTTP provider, outside timed load. Timings are inclusive for nested stages, so they must not be added together. Each diagnostic ran once; SQL counts and the removed work identify the change more directly than a universal timing claim.

| Diagnostic | Release | Optimized |
| --- | ---: | ---: |
| Processing SQL statements / 200 events, including transaction statements | 5,600 | 5,200 |
| Invoice validation calls | 400 | 200 |
| Processing CPU seconds | 1.869 | 1.624 |
| Posting CPU seconds, included above | 1.085 | 0.933 |
| Processing wall seconds | 5.313 | 4.932 |

`PostEffects` now reuses its verified/posted payment when computing invoice status, eliminating the second invoice reload and the payment re-read on the normal fresh-payment path. Without a payment snapshot it still consults the local payment. It skips unchanged invoice mapping/status writes and their validations. Customer/event locking, transactions, database uniqueness, remote identity checks, refund sums and read-version invalidation remain enabled. A new regression checks that an incomplete later snapshot cannot regress a fully refunded invoice.

Application concurrency is a separate tuning factor: `BENCHMARK_THREADS=8` sets eight API/Sidekiq threads and matching database pools; the release baseline uses five. The provider already has eight threads. Container CPU/memory caps are unchanged. Before/after capacity differences therefore measure the combined code change and concurrency tuning, not an isolated code-only speedup. The initial test image also exposed a missing `tmp` directory for type probes; `bin/ci` now creates it. Final image acceptance passes 225 RSpec examples, 151 linted Ruby files, Sorbet, positive/negative type probes, schema RBI drift and autoloading; application-only coverage is 1,257/1,289 lines (97.51%) and 234/275 branches (85.09%). The clock-parser regression passes two Python tests.

## Actual sustained results

The 100/s five-minute before/after tests share their client, fixture variant and cgroup caps; intended changes are the code and thread tuning. The longer 95/s trial and four-vCPU trial are separate scenarios. No failed experiment is replaced by a successful one.

| Build / VM / threads | Offering | Minimum full minute | HTTP failures / client drops | Sampled peak / ending pending | Full gate |
| --- | --- | ---: | ---: | ---: | --- |
| [Release / 2 CPU / 5](release-before/summary.json) | 100/s × 5 min | 4,196 | 0 / 113 | 1,548 / 1,349 | Failed |
| [Optimized / 2 CPU / 8](optimized-100rps/summary.json) | 100/s × 5 min | 5,216 | 0 / 0 | 145 / 0 | Failed |
| [Optimized / 2 CPU / 8](confirmation-2cpu-95rps/summary.json) | 95/s × 7 min | 3,765 | 0 / 1,167 | 2,740 / 2,056 | Failed |
| [Optimized / 4 CPU / 8](scaled-4cpu-100rps/summary.json) | 100/s × 7 min | 5,381 | 0 / 0 | 349 / 0 | Failed |

Four-vCPU complete-minute counts: **5,399 / 5,399 / 5,400 / 5,401 / 5,400 / 5,381 / 5,418**. These are stored completion timestamps within seven full minute windows, excluding warm-up and drain. 37,798 completions fall inside the exact timed windows; the final request/drain snapshot contains all 37,800. 42,000 deliveries produced exactly 37,800 processed distinct events and 33,600 new payment effects; the remaining deliveries repeat event IDs or financial identities. The expected effect count equals the actual count. Warm-up adds 100 separate payments/events outside timing. All eight accounting checks are clean, with no dead/review/retry work.

The final HTTP acknowledgment p95 was **133.06 ms**; receipt-to-processing completion p95 **1,153.07 ms**. Acknowledgment latency is not reconciliation latency. Queue bursts therefore remain meaningful even though all minute counts exceed 5,000 and ending backlog/trend are zero. **Do not call this an all-criteria pass or a sub-second reconciliation result.** The predeclared 100-pending guard was not relaxed.

The seven-minute two-vCPU attempt had 1,167 client drops, a 3,765-event minimum minute and a sampled backlog peak of 2,740. Its worker recorded zero cgroup throttle periods; VM CPU pressure was high, while the database wait snapshot mostly showed clients idle/in transactions rather than a blocking-lock pile-up. This supports testing more VM CPU, but does not prove a single exclusive bottleneck. Four CPU allocation, code changes and concurrency must all remain part of the capacity claim.

## Evidence and limits

[Commands](commands.md), [comparison](comparison.json), [two-CPU environment](environment.json), [four-CPU environment](environment-4cpu.json), [source comparison](source-comparison.json), [image IDs](images.json), [profile before](profile-before.json), [profile after](profile-after.json), [quality output](checks-optimized.log), and [clock-parser regressions](python-clock-tests.log) identify the measurements. Per-run directories retain summaries, clock calibration, observations, raw requests and accounting snapshots. Request NDJSON is compressed losslessly for storage; the compression register records uncompressed hashes. Historical Milestone 3/4 evidence remains unchanged.

The benchmark uses synthetic canonical resources and a local read-only provider with the real SDK. **No external Stripe throughput or charge-creation rate was tested.** The result does not cover every event mix, workload or production failure mode. Financial regression coverage includes concurrency, rollback, reverse delivery, partial/full refunds and incomplete snapshots; this follow-up did not repeat the separate 180,000-delivery service-level all-invoice replay.

[Restoration proof](restoration.json): all 11 original mixed-fixture fingerprints match; benchmark services are stopped, the VM is restored to two CPUs/four GiB, main readiness passed and the development database remains at 3 invoices/payments, 6 refunds and 12 journals/24 rows with eight clean accounting checks. No commits or pushes were made for this follow-up.
