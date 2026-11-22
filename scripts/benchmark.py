#!/usr/bin/env python3
"""Open-loop local benchmark. Standard library only; never contacts Stripe."""
import argparse
import concurrent.futures
import hashlib
import hmac
import http.client
import json
import math
import random
import re
import threading
import time
from pathlib import Path
from urllib.parse import urlparse

API_KEY = 'ledgerly-benchmark-local'
SIGNING_SECRET = b'whsec_benchmark'
API_VERSION = '2026-11-18.endive'
BASE = urlparse('http://127.0.0.1:3002')
LOCAL = threading.local()


def request(method, path, body=None, signed=False):
    if not hasattr(LOCAL, 'connection'):
        LOCAL.connection = http.client.HTTPConnection(BASE.hostname, BASE.port, timeout=20)
    headers = {'Authorization': 'Bearer ' + API_KEY, 'Content-Type': 'application/json'}
    if signed:
        stamp = str(int(time.time()))
        signature = hmac.new(SIGNING_SECRET, stamp.encode() + b'.' + body, hashlib.sha256).hexdigest()
        headers['Stripe-Signature'] = 't=' + stamp + ',v1=' + signature
    try:
        LOCAL.connection.request(method, path, body=body, headers=headers)
        response = LOCAL.connection.getresponse()
        raw = response.read()
        return response.status, json.loads(raw), {key.lower(): value for key, value in response.getheaders()}, len(raw)
    except Exception:
        LOCAL.connection.close()
        del LOCAL.connection
        raise


def get(path):
    status, body, _, _ = request('GET', path)
    if status != 200:
        raise RuntimeError('Observation failed: ' + str(status))
    return body


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    index = (len(ordered) - 1) * fraction
    lower, upper = math.floor(index), math.ceil(index)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (index - lower)


def distribution(values):
    return {'p50': percentile(values, .50), 'p95': percentile(values, .95), 'p99': percentile(values, .99),
            'max': max(values) if values else None}


def event(identity, invoice, kind='invoice.paid'):
    prefix, object_type = ('ch', 'charge') if kind == 'charge.refunded' else ('in', 'invoice')
    return json.dumps({'id': identity, 'object': 'event', 'type': kind, 'api_version': API_VERSION,
                       'livemode': False, 'created': int(time.time()),
                       'data': {'object': {'id': f'{prefix}_bench_{invoice}', 'object': object_type}}},
                      separators=(',', ':')).encode()


def run_arrivals(rate, duration, work, raw_path, workers=32, max_inflight=64, on_start=None):
    results = []
    lock = threading.Lock()
    capacity = threading.BoundedSemaphore(max_inflight)
    start = time.monotonic() + .1
    started_at_unix = time.time() + .1
    if on_start:
        on_start({'offering_started_at_unix': started_at_unix})
    dropped = 0

    def execute(index, scheduled):
        actual = time.monotonic()
        row = {'index': index, 'start_delay_ms': (actual - scheduled) * 1000, 'started_seconds': actual - start}
        try:
            method, path, payload, signed = work(index)
            code, body, headers, size = request(method, path, payload, signed)
            row.update(status=code, response_bytes=size, valid=code == 200 and ('data' in body or body.get('received') is True),
                       cache_status=headers.get('x-benchmark-cache-status', 'off'),
                       sql_queries=int(headers.get('x-benchmark-sql-queries', 0)),
                       sql_ms=float(headers.get('x-benchmark-sql-ms', 0)))
            if signed:
                row['duplicate'] = body.get('duplicate')
            else:
                row['response_sha256'] = hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()
        except Exception as error:
            row.update(status=0, valid=False, error=type(error).__name__)
        finally:
            end = time.monotonic()
            row.update(http_ms=(end - actual) * 1000, elapsed_ms=(end - scheduled) * 1000,
                       completed_seconds=end - start)
            with lock:
                results.append(row)
            capacity.release()

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        for index in range(int(rate * duration)):
            scheduled = start + index / rate
            delay = scheduled - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            if capacity.acquire(blocking=False):
                pool.submit(execute, index, scheduled)
            else:
                dropped += 1
    elapsed = time.monotonic() - start
    raw_path.write_text(''.join(json.dumps(row, sort_keys=True) + '\n' for row in sorted(results, key=lambda r: r['index'])))
    return {'offered_requests': int(rate * duration), 'completed_requests': len(results), 'dropped_arrivals': dropped,
            'offering_started_at_unix': started_at_unix, 'workers': workers, 'max_inflight': max_inflight,
            'failures': sum(not row['valid'] for row in results), 'arrival_rate_per_second': rate,
            'offering_duration_seconds': duration, 'including_tail_seconds': elapsed,
            'http_latency_ms': distribution([row['http_ms'] for row in results]),
            'scheduled_to_completion_ms': distribution([row['elapsed_ms'] for row in results]),
            'generator_start_delay_ms': distribution([row['start_delay_ms'] for row in results]),
            'sql_queries_per_request': distribution([row.get('sql_queries', 0) for row in results]),
            'sql_time_ms': distribution([row.get('sql_ms', 0) for row in results]),
            'cache_status_counts': {status: sum(row.get('cache_status') == status for row in results) for status in ['hit', 'miss', 'off']},
            'duplicate_acknowledgments': sum(row.get('duplicate') is True for row in results),
            'response_hashes': sorted(set(row.get('response_sha256') for row in results if row.get('response_sha256')))}, results


def reads(args, output):
    scenarios = {'invoice_list_first': '/api/v1/customers/1/invoices?page=1&per_page=100',
                 'invoice_list_deep': '/api/v1/customers/1/invoices?page=10&per_page=100',
                 'customer_balance': '/api/v1/customers/1/balance'}
    report = {'cache_state': 'Application cache status recorded per request; optional cold first observation clears only read-cache keys; database/OS caches never flushed', 'scenarios': {}}
    for name, path in scenarios.items():
        sample = get(path)
        if 'invoice_list' in name:
            assert len(sample['data']) == 100 and sample['meta']['total'] == 1000
        else:
            assert sample['data']['customer_id'] == 1 and sample['data']['balances']
        if args.cold_first:
            code, _, _, _ = request('POST', '/_benchmark/cache/clear', b'{}')
            assert code == 200
        work = lambda _index: ('GET', path, None, False)
        first, _ = run_arrivals(1, 1, work, output / (name + '-first.ndjson'))
        warmup, _ = run_arrivals(args.rate, args.warmup, work, output / (name + '-warmup.ndjson'))
        measured, _ = run_arrivals(args.rate, args.duration, work, output / (name + '.ndjson'))
        report['scenarios'][name] = {'path': path, 'first_observation': first, 'warmup': warmup, 'measured': measured}
        print(json.dumps({'scenario': name, 'p95_ms': measured['http_latency_ms']['p95'], 'failures': measured['failures']}), flush=True)
    return report


def wait_drain(since, expected, timeout=180):
    deadline = time.monotonic() + timeout
    while True:
        current = get('/_benchmark/stats?since=' + str(since))
        if current['processed'] == expected and not current['received']:
            return current
        if current['dead'] or current['review'] or current['dead_size']:
            raise RuntimeError('Webhook processing entered dead/review: ' + json.dumps(current))
        if time.monotonic() >= deadline:
            raise RuntimeError('Processing did not drain: ' + json.dumps(current))
        time.sleep(1)


def webhooks(args, output):
    candidates = [i for i in range(1, 50001) if i % 10 < 2]
    random.Random(20261121).shuffle(candidates)
    required = int(args.rate * args.duration)
    if required + 100 > len(candidates):
        raise ValueError('Workload exceeds fresh-payment fixture pool')
    before = get('/_benchmark/dataset')
    output.joinpath('dataset-before.json').write_text(json.dumps(before, indent=2) + '\n')
    since = get('/_benchmark/stats')['max_event_id']
    warm = [event(f'evt_bench_{args.run_id}_warm_{n}', i) for n, i in enumerate(candidates[-100:])]
    for raw in warm:
        code, _, _, _ = request('POST', '/webhooks/stripe', raw, True)
        assert code == 200
    wait_drain(since, 100, args.drain_timeout)
    since = get('/_benchmark/stats')['max_event_id']
    after_warmup = get('/_benchmark/dataset')
    output.joinpath('dataset-after-warmup.json').write_text(json.dumps(after_warmup, indent=2) + '\n')
    payloads = []
    for n in range(required):
        # 10% repeated IDs; another 10% distinct event IDs describe the previous payment.
        if n % 10 == 9:
            payloads.append(payloads[-1])
        else:
            invoice = candidates[n - 1 if n % 10 == 8 else n]
            payloads.append(event(f'evt_bench_{args.run_id}_{n}', invoice))
    samples, observer_errors, stop = [], [], threading.Event()
    start = time.monotonic()

    def observe():
        try:
            while not stop.is_set():
                sample = get('/_benchmark/stats?since=' + str(since))
                sample['elapsed_seconds'] = time.monotonic() - start
                samples.append(sample)
                with output.joinpath('queue-samples.ndjson').open('a') as stream:
                    stream.write(json.dumps(sample) + '\n')
                stop.wait(2)
        except Exception as error:
            observer_errors.append(type(error).__name__)

    observer = threading.Thread(target=observe, daemon=True)
    observer.start()
    drain_error = None
    try:
        summary, rows = run_arrivals(args.rate, args.duration,
                                    lambda n: ('POST', '/webhooks/stripe', payloads[n], True), output / 'webhooks.ndjson')
        accepted_unique = len({payloads[row['index']] for row in rows if row['valid']})
        at_end = get('/_benchmark/stats?since=' + str(since))
        output.joinpath('at-end-of-offering.json').write_text(json.dumps(at_end, indent=2) + '\n')
        try:
            complete = wait_drain(since, accepted_unique, args.drain_timeout)
        except RuntimeError as error:
            drain_error = str(error)
            complete = get('/_benchmark/stats?since=' + str(since))
        total_seconds = time.monotonic() - start
    finally:
        stop.set()
        observer.join()
    assert not observer_errors, observer_errors
    after = get('/_benchmark/dataset')
    expected_effects = len({json.loads(payloads[row['index']])['data']['object']['id'] for row in rows if row['valid']})
    actual_effects = after['financial_counts']['stripe_payments'] - after_warmup['financial_counts']['stripe_payments']
    fully_drained = complete['processed'] == accepted_unique and complete['received'] == 0
    if fully_drained:
        assert actual_effects == expected_effects, (actual_effects, expected_effects)
    output.joinpath('queue-samples.json').write_text(json.dumps(samples, indent=2) + '\n')
    return {'fully_drained': fully_drained, 'drain_error': drain_error, 'http': summary, 'before': before, 'after_warmup': after_warmup, 'after': after,
            'expected_new_payment_effects': expected_effects, 'unique_accepted_events': accepted_unique, 'at_end_of_offering': at_end, 'after_drain': complete,
            'observation_including_drain_seconds': total_seconds,
            'unique_processed_per_minute_during_offering': at_end['processed'] / summary['including_tail_seconds'] * 60,
            'unique_processed_per_minute_including_drain': complete['processed'] / total_seconds * 60,
            'new_payment_effects': after['financial_counts']['stripe_payments'] - after_warmup['financial_counts']['stripe_payments'],
            'new_refund_effects': after['financial_counts']['stripe_refunds'] - after_warmup['financial_counts']['stripe_refunds'],
            'provider': 'Isolated read-only HTTP stub, fixed 2ms minimum delay per SDK request; no live Stripe calls'}


def replay(args, output):
    # First deliveries shuffled: refunds may precede paid/failure notifications.
    before = get('/_benchmark/dataset')
    since = get('/_benchmark/stats')['max_event_id']
    invoices = list(range(1, 101))
    payloads = [event(f'evt_bench_{args.run_id}_{i}_{kind.replace(chr(46), chr(95))}', i, kind)
                for i in invoices for kind in ['charge.refunded', 'invoice.paid', 'invoice.payment_failed']]
    random.Random(20261121).shuffle(payloads)
    unique = len(payloads)
    payloads *= 3
    random.Random(20261122).shuffle(payloads)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        outcomes = list(pool.map(lambda raw: request('POST', '/webhooks/stripe', raw, True)[0], payloads))
    assert all(code == 200 for code in outcomes)
    complete = wait_drain(since, unique)
    dataset = get('/_benchmark/dataset')
    new_payments = dataset['financial_counts']['stripe_payments'] - before['financial_counts']['stripe_payments']
    assert new_payments == 20, new_payments
    return {'passed': True, 'new_payment_effects': new_payments, 'fixture_invoice_count': 50000, 'sampled_invoices': 100, 'deliveries': len(payloads),
            'distinct_events': unique, 'processing': complete, 'dataset_after': dataset}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('scenario', choices=['reads', 'webhooks', 'replay'])
    parser.add_argument('--output', required=True)
    parser.add_argument('--rate', type=float, default=40)
    parser.add_argument('--duration', type=float, default=20)
    parser.add_argument('--warmup', type=float, default=5)
    parser.add_argument('--run-id', default='baseline_v1')
    parser.add_argument('--cold-first', action='store_true')
    parser.add_argument('--drain-timeout', type=float, default=180)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_]{1,80}', args.run_id):
        parser.error('Run ID must contain only letters, digits, or underscores')
    if args.rate <= 0 or args.duration <= 0 or args.warmup < 0:
        parser.error('Rates/duration must be positive and warmup nonnegative')
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    started = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    report = globals()[args.scenario](args, output)
    report.update(started_at_utc=started, scenario=args.scenario, arguments=vars(args), generator='Python stdlib open-loop, 32 threads, 64 in-flight limit')
    output.joinpath('summary.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'saved': str(output / 'summary.json')}))
    if args.scenario == 'reads':
        assert all(v['measured']['failures'] == 0 and v['measured']['dropped_arrivals'] == 0 for v in report['scenarios'].values())
    elif args.scenario == 'webhooks':
        assert report['http']['failures'] == 0 and report['http']['dropped_arrivals'] == 0 and report['fully_drained']


if __name__ == '__main__':
    main()
