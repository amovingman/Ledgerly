# Queue-spike follow-up, 2026-11-22

Follow [ROADMAP.md](../../../ROADMAP.md). **The clean three-worker run passed the original sustained gate and both strict pending-peak checks:** five-second sampled peak **42**, record-timestamp reconstructed peak **76**, with **5,395–5,403 distinct completions in every minute for seven minutes**. Ruby timing instrumentation was disabled. This is one accepted clean run of the three-worker configuration; earlier misses remain below. The [earlier sustained result](../2026-11-22-sustained-v1/README.md) remains unchanged: throughput passed on four VM CPUs, while the sampled pending peak of 349 missed the conservative queue guard.

This follow-up keeps the four-vCPU/four-GiB configured Docker VM, API pool of eight, 100 signed deliveries/s for 420 seconds, 64 client threads/256-request capacity, seed 20261121, fresh-payment 50k variant, 100 reserved warm-up events, duplicate mix, fixed 2 ms local provider delay, recovery, database constraints and accounting checks. Ten percent of deliveries repeat an event ID; another ten percent use distinct IDs for the same payment. Thus 42,000 offered deliveries yield up to 37,800 distinct events and 33,600 new payment effects, outside warm-up. No external Stripe load or charge creation is tested.

## Profiling and changes

Optional `BENCHMARK_PROFILE_SPIKES=1` instrumentation records jobs taking at least 100 ms, with provider/snapshot/posting/SQL wall timings, thread CPU and overlapping process-wide GC time. Stage timings overlap and must not be added; GC intervals can overlap across threads. Slow-job records are a thresholded subset, not a complete latency distribution. A persistent shell per container samples CPU throttling and CPU/I/O pressure at approximately one-second intervals.

The one-process/eight-thread seven-minute profile reproduced the miss: sampled pending peak **288**, reconstructed timestamp peak **426**, minimum complete minute **5,341**, all 37,800 accepted events and exactly 33,600 new payment effects, clean accounting. Slow intervals delayed several jobs together. One observed job took about 576 ms wall/26 ms thread CPU with 85 ms of overlapping process GC; SQL and provider waits both increased. At that interval container quotas showed no significant throttling, CPU scheduling pressure rose and I/O pressure remained low. This does not isolate one exclusive cause; the experiment tests whether separate worker processes can absorb those pauses/bursts.

The candidate uses **two Sidekiq processes × four threads**, retaining eight total worker threads and database connections. The API stays at eight threads. Each worker retains its 1 CPU/512 MiB cap, so **aggregate worker caps rise from 1 CPU/512 MiB to 2 CPUs/1 GiB** within the same four-vCPU VM. This is process isolation plus additional burst CPU capacity, not a code-only or equal aggregate-resource comparison. No financial service/model code changes in this follow-up. An independent `BENCHMARK_WORKER_THREADS` setting defaults to the previous `BENCHMARK_THREADS` behavior.

## Measurement and acceptance

Keep the existing sustained gate: >=5,000 distinct completions in each complete minute, no HTTP failures/client drops, ending pending <=25, measured post-first-minute trend <=0.1 event/s, all accepted events drained, expected payment effects and eight clean accounting checks, no retry/dead/review work. For this request both sampled and reconstructed pending peaks must be **strictly below 100**. Five-second samples alone are insufficient evidence for short spikes.

`queue_timeline.py` orders receipt creation (+1) and processing timestamps (-1) across all accepted timed event lifetimes, including drain, grouping equal timestamps before summation. This is a record-timestamp estimate, not transaction commit order: receipt timestamps precede receipt commits, and processed timestamps precede effect commits. Both estimates and the sampled observations are retained; do not call this an exact instantaneous Redis queue maximum. Stored complete-minute counts continue to exclude warm-up/drain and use the unchanged server-clock calibration.

Final image checks passed **225 specs**, **152 Ruby files lint clean**, Sorbet, positive/negative type probes, schema RBI drift and autoloading. Application-only coverage: 1,257/1,289 lines (97.51%); 234/275 branches (85.09%). The post-run timeline initially encountered PostgreSQL numeric serialization as `426.0`; its output is now explicitly cast to bigint. The timed run was not repeated or discarded for that reporting fix.

The two × four worker profile passed five-second sampling at 31 but still missed the reconstructed guard at 127. Two × six workers worsened the peaks to 158/219. PostgreSQL then used a **10,000 µs quota per 10,000 µs period**, preserving the original one-core average allowance while reducing the length of a quota-exhaustion stall; the original window was 100,000/100,000. Kernel `cpu.max` values are retained. Database durability, locks and integrity constraints were unchanged. This restarts the benchmark PG container, so shared-buffer state can differ; no exclusive causal speedup is claimed.

With two × four workers and the shorter period, the instrumented trial passed at 61/88, but the clean confirmation missed at 99/147. The accepted clean configuration therefore uses **three processes × four threads = twelve worker threads**, each retaining a 1 CPU/512 MiB cap: **aggregate worker caps are 3 CPUs/1.5 GiB**, up from the initial 1 CPU/512 MiB. API remains eight threads/1 CPU/512 MiB; PG remains 1 CPU/768 MiB; provider eight threads/0.5 CPU/128 MiB; Redis/recovery caps and the four-vCPU/four-GiB configured VM are unchanged. This is process isolation, added worker burst capacity and DB scheduling tuning—not an equal aggregate-resource or code-only improvement. No financial service/model code changed during this follow-up.

## Actual results

All rows offer 100 signed deliveries/s for 420 seconds using the same fixture preparation, provider contract and client settings. Every row has zero HTTP failures/client capacity drops, exactly 37,800 processed distinct events / 33,600 new payment effects outside warm-up, and clean accounting. The stricter gate preserves every original throughput/drain/integrity requirement and additionally rejects either pending estimate reaching 100.

| Workers × threads | PG quota/period µs | Ruby profile | Minimum complete minute | Sampled / timestamp peak | Original / stricter gate |
| --- | --- | --- | ---: | ---: | --- |
| [1 × 8](one-worker/queue-acceptance.json) | 100000/100000 | On | 5,341 | 288 / 426 | Fail / Fail |
| [2 × 4](two-workers-four-threads/queue-acceptance.json) | 100000/100000 | On | 5,397 | 31 / 127 | Pass / Fail |
| [2 × 6](two-workers-six-threads/queue-acceptance.json) | 100000/100000 | On | 5,348 | 158 / 219 | Fail / Fail |
| [2 × 4](short-db-period/queue-acceptance.json) | 10000/10000 | On | 5,353 | 61 / 88 | Pass / Pass |
| [2 × 4](two-workers-clean-confirmation/queue-acceptance.json) | 10000/10000 | Off | 5,394 | 99 / 147 | Pass / Fail |
| [3 × 4](three-workers-clean/queue-acceptance.json) | 10000/10000 | Off | 5,395 | 42 / 76 | Pass / Pass |

Accepted full-minute counts: **5,398 / 5,403 / 5,395 / 5,403 / 5,401 / 5,399 / 5,396**. Exactly 37,795 completions fall within those seven timestamp windows; all 37,800 accepted distinct events completed by the final observation/drain. Warm-up adds 100 separate events/payment effects outside timing. Ending pending work is zero, sampled trend is slightly negative, and retry/dead/review work is zero. All eight accounting checks pass and payment effects equal the independently expected identity count.

In that clean run, client HTTP acknowledgment p95 was **288.27 ms** and record-creation→`processed_at` p95 **207.79 ms**. These have different start/end points; neither is an external Stripe latency measurement. Pending reconstruction is a timestamp estimate, with the commit-order limitations stated above.

[Comparison](comparison.json), [accepted summary](three-workers-clean/summary.json), [stricter acceptance](three-workers-clean/queue-acceptance.json), [timeline](three-workers-clean/queue-timeline.json), [runtime limits](environment-three-workers.json), [quality output](checks.log), [Python regressions](python-tests.log), [profile example/counters](profile-one-worker.json), and [reproduction](commands.md) provide the evidence. The benchmark image is identical across experiments; flags/process layout/resource settings vary as recorded. Archives/manifests identify the measured public source, and raw request/slow-job NDJSON is compressed losslessly with original hashes/row counts in the compression register.

The test is local reconciliation against a read-only HTTP provider using the pinned real SDK. No actual Stripe load or outgoing charge creation was tested. Broader financial behavior remains covered by the existing suite and prior all-invoice/sandbox acceptance; the separate 180,000-delivery all-invoice service replay was not repeated for these benchmark-only changes. No commits or pushes were made.

[Restoration proof](restoration.json): original mixed fixture matches all 11 fingerprints, benchmark services are stopped, PG is back at 100000/100000, and the VM is back at two CPUs/four GiB. Development readiness passes and its 3 invoices/payments, 6 refunds, 12 journals/24 rows and eight-check audit are unchanged.

[Measured source archive](measured-source.tar.gz), [source manifest](source-manifest.json), [image identity](image.json), [image/source verification](image-source-verification.json), [fixture comparison](fixture-comparison.json), and [compression register](compression-register.json) complete the reproducible evidence.

[Core-source comparison](financial-source-unchanged.json) confirms the application model/service/controller files match the earlier sustained-v1 optimized image. The Git-base patch also contains that earlier local optimization; it is not a new financial change in this queue follow-up.
