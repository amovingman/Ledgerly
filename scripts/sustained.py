#!/usr/bin/env python3
"""Five-minute signed fresh-payment load; uses only the isolated benchmark service."""
import argparse
from datetime import datetime
import importlib.util
import json
import os
from pathlib import Path
import random
import subprocess
import threading
import time

spec = importlib.util.spec_from_file_location('benchmark', Path(__file__).with_name('benchmark.py'))
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


def get(path):
    # Observation connections can sit idle for the whole five-minute offering.
    # Use fresh connections; never retry or change the measured POST requests.
    if hasattr(bench.LOCAL, 'connection'):
        bench.LOCAL.connection.close()
        del bench.LOCAL.connection
    return bench.get(path)


def calibrate_clock():
    samples = []
    for _ in range(5):
        before = time.time()
        stats = get('/_benchmark/stats')
        after = time.time()
        database = database_timestamp(stats['database_time'])
        samples.append({'rtt_seconds': after-before, 'offset_seconds': database-(before+after)/2,
                        'offset_min': database-after, 'offset_max': database-before})
    best = min(samples, key=lambda s: s['rtt_seconds'])
    return {'samples': samples, 'selected': best}


def database_timestamp(value):
    # Python 3.9 fromisoformat rejects PG's valid 1/2/4/5-digit fractions.
    for pattern in ('%Y-%m-%dT%H:%M:%S.%f%z', '%Y-%m-%dT%H:%M:%S%z'):
        try:
            return datetime.strptime(value, pattern).timestamp()
        except ValueError:
            pass
    raise ValueError('Unsupported PostgreSQL timestamp')


def completion_windows(args, since, start):
    # After the timed offering/drain. Exact minute buckets use stored completion
    # timestamps and calibrated PG time, rather than extrapolating a drained burst.
    ruby = '''start=Time.at(%s).utc; finish=start+%s
connection=ApplicationRecord.connection
sql=ApplicationRecord.sanitize_sql_array(["SELECT floor(extract(epoch FROM processed_at-?::timestamptz)/60)::int AS minute,count(*) AS completed FROM stripe_events WHERE id>? AND status='processed' AND processed_at>=? AND processed_at<? GROUP BY 1 ORDER BY 1",start,%s,start,finish])
puts 'WINDOWS='+JSON.generate(connection.select_all(sql).to_a)
''' % (repr(start), args.duration, since)
    environment = dict(os.environ, BENCHMARK_IMAGE=args.image)
    result = subprocess.run(['docker','compose','-f','compose.benchmark.yaml','exec','-T','api','bin/rails','runner','-'],
                            input=ruby, text=True, capture_output=True, check=True, env=environment)
    return json.loads(next(line.partition('=')[2] for line in result.stdout.splitlines() if line.startswith('WINDOWS=')))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rate', type=float, default=100)
    parser.add_argument('--duration', type=int, default=300)
    parser.add_argument('--workers', type=int, default=64)
    parser.add_argument('--max-inflight', type=int, default=256)
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--image', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    if not bench.re.fullmatch(r'[A-Za-z0-9_]{1,80}', args.run_id):
        parser.error('Invalid run ID')
    if args.duration <= 0 or args.duration % 60 or args.rate <= 0 or args.workers <= 0 or args.max_inflight < args.workers:
        parser.error('Use positive whole-minute duration and a bounded client pool')
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=False)
    before = get('/_benchmark/dataset')
    assert before['counts']['invoices'] == 50000
    assert before['financial_counts']['stripe_payments'] == before['financial_counts']['stripe_refunds'] == 0
    assert before['invoice_statuses'] == {'issued': 50000}
    candidates = [i for i in range(1,50001) if i % 20 not in (2,3)]
    random.Random(20261121).shuffle(candidates)
    count = int(args.rate * args.duration)
    if count + 100 > len(candidates):
        parser.error('Not enough fresh fixture invoices for this run')
    save = lambda name, data: (output/name).write_text(json.dumps(data,indent=2)+'\n')
    save('dataset-before.json', before)
    since = get('/_benchmark/stats')['max_event_id'] or 0
    for n, invoice in enumerate(candidates[-100:]):
        status,_,_,_ = bench.request('POST','/webhooks/stripe',bench.event(f'evt_{args.run_id}_warm_{n}',invoice),True)
        assert status == 200
    bench.wait_drain(since,100)
    after_warmup = get('/_benchmark/dataset')
    since = get('/_benchmark/stats')['max_event_id']
    save('observation-boundary.json', {'since': since, 'after_warmup': after_warmup})
    payloads = []
    for n in range(count):
        payloads.append(payloads[-1] if n % 10 == 9 else
                        bench.event(f'evt_{args.run_id}_{n}',candidates[n-1 if n % 10 == 8 else n]))
    calibration = calibrate_clock()
    save('clock-calibration.json',calibration)
    samples, errors, stop = [], [], threading.Event()
    started = time.monotonic()

    def observe():
        try:
            while not stop.is_set():
                row = get('/_benchmark/stats?since='+str(since))
                row['elapsed_seconds'] = time.monotonic()-started
                samples.append(row)
                with (output/'queue-samples.ndjson').open('a') as stream:
                    stream.write(json.dumps(row)+'\n')
                stop.wait(5)
        except Exception as error:
            errors.append(type(error).__name__)

    observer = threading.Thread(target=observe,daemon=True)
    observer.start()
    try:
        http, rows = bench.run_arrivals(args.rate,args.duration,
            lambda n: ('POST','/webhooks/stripe',payloads[n],True),output/'webhooks.ndjson',args.workers,args.max_inflight,
            on_start=lambda data: save('offering-start.json', data))
        save('http.json', http)
        at_end = get('/_benchmark/stats?since='+str(since))
        save('at-end.json', at_end)
        accepted = len({payloads[row['index']] for row in rows if row['valid']})
        drain_error = None
        try:
            complete = bench.wait_drain(since,accepted,180)
        except RuntimeError as error:
            drain_error = str(error)
            complete = get('/_benchmark/stats?since='+str(since))
        save('after-drain.json', complete)
        elapsed = time.monotonic()-started
    finally:
        stop.set()
        observer.join()
    after = get('/_benchmark/dataset')
    save('dataset-after.json', after)
    windows = completion_windows(args,since,http['offering_started_at_unix']+calibration['selected']['offset_seconds'])
    expected_effects = len({json.loads(payloads[r['index']])['data']['object']['id'] for r in rows if r['valid']})
    actual_effects = after['financial_counts']['stripe_payments']-after_warmup['financial_counts']['stripe_payments']
    minute_counts = {int(w['minute']):int(w['completed']) for w in windows}
    minimum_minute = min(minute_counts.get(i,0) for i in range(args.duration//60))
    measured_samples = [s for s in samples if 60 <= s['elapsed_seconds'] <= args.duration]
    trend = (measured_samples[-1]['received']-measured_samples[0]['received']) / (measured_samples[-1]['elapsed_seconds']-measured_samples[0]['elapsed_seconds']) if len(measured_samples)>1 else None
    drained = complete['processed']==accepted and complete['received']==0
    integrity = drained and actual_effects==expected_effects and not any(after['violations'].values())
    # Allow normal sub-second work in flight, not a rising processing debt.
    bounded_queue = trend is not None and trend <= .1 and at_end['received'] <= 25 and max(s['received'] for s in samples)<=100
    passed = (args.duration>=300 and http['failures']==http['dropped_arrivals']==0 and minimum_minute>=5000
              and bounded_queue and integrity and not errors and complete['retry_size']==complete['dead_size']==complete['review']==0)
    report = {'passed':passed,'arguments':vars(args),'provider':'Read-only local HTTP stub, unchanged 2ms minimum per SDK call; no external Stripe',
              'clock_calibration':calibration,'http':http,'at_end_of_offering':at_end,'after_drain':complete,
              'unique_accepted_events':accepted,'completed_per_minute':minute_counts,'minimum_complete_minute':minimum_minute,
              'processed_per_minute_during_offering':at_end['processed']/http['including_tail_seconds']*60,
              'observation_including_drain_seconds':elapsed,'drain_error':drain_error,'observer_errors':errors,
              'queue_trend_events_per_second':trend,'bounded_queue':bounded_queue,'peak_received':max(s['received'] for s in samples),
              'expected_new_payments':expected_effects,'actual_new_payments':actual_effects,'integrity_passed':integrity,
              'before':before,'after_warmup':after_warmup,'after':after}
    save('summary.json',report)
    print(json.dumps({k:report[k] for k in ['passed','minimum_complete_minute','completed_per_minute','peak_received','queue_trend_events_per_second','actual_new_payments','integrity_passed']}),flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
