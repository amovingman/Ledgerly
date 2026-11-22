#!/usr/bin/env python3
"""Live local-API acceptance check; requires Python 3 standard library only.

Creates one synthetic customer, plan, subscription and invoice. It does not
invoke Stripe. Run from the repository root against a disposable dev stack.
"""
import json
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from urllib.parse import urlparse
from uuid import uuid4

# Run from the repository root. This creates synthetic data in the local API.
# API_KEY may be exported or supplied by the ignored root .env file.
api_key = os.environ.get('API_KEY')
if not api_key:
    api_key = next(line.partition('=')[2].strip().strip("'\"") for line in Path('.env').read_text().splitlines() if line.startswith('API_KEY='))
base = os.environ.get('API_BASE_URL', 'http://127.0.0.1:3000').rstrip('/')
assert urlparse(base).hostname in ('127.0.0.1', 'localhost'), 'This verification client only targets a local API.'
assert urlparse(base).scheme == 'http', 'Use the local development HTTP endpoint.'

def call(method, path, body=None, key=None, expected=(200, 201)):
    headers = {'Authorization': 'Bearer ' + api_key, 'Content-Type': 'application/json'}
    if key:
        headers['Idempotency-Key'] = key
    request = Request(base + path, method=method, headers=headers, data=None if body is None else json.dumps(body).encode())
    try:
        response = urlopen(request, timeout=15)
    except HTTPError as error:
        response = error
    payload = json.load(response)
    assert response.status in expected, (method, path, response.status, payload)
    return response.status, payload

end = datetime.now(timezone.utc).replace(day=1, hour=0, minute=0, second=0, microsecond=0)
start = (end - timedelta(days=1)).replace(day=1)
period = start.isoformat(timespec='microseconds').replace('+00:00', 'Z')
customer = call('POST', '/api/v1/customers', {'customer': {'name': 'HTTP verification', 'email': f'{uuid4()}@example.test'}})[1]['data']
plan = call('POST', '/api/v1/plans', {'plan': {'name': 'API calls', 'metric': 'api_calls', 'unit_amount': 7, 'currency': 'USD'}})[1]['data']
subscription = call('POST', '/api/v1/subscriptions', {'subscription': {'customer_id': customer['id'], 'plan_id': plan['id'], 'starts_at': period}})[1]['data']
usage = {'usage_event': {'customer_id': customer['id'], 'subscription_id': subscription['id'], 'metric': 'api_calls', 'quantity': 10, 'occurred_at': period}}
key = 'live-' + str(uuid4())
with ThreadPoolExecutor(max_workers=4) as pool:
    usages = list(pool.map(lambda _: call('POST', '/api/v1/usage_events', usage, key=key), range(4)))
assert sorted(status for status, _ in usages) == [200, 200, 200, 201]
assert len({result['data']['id'] for _, result in usages}) == 1
original_usage = usages[0][1]
invoice_path = f'/api/v1/subscriptions/{subscription["id"]}/invoices'
with ThreadPoolExecutor(max_workers=4) as pool:
    invoices = list(pool.map(lambda _: call('POST', invoice_path, {'invoice': {'period_start': period}}), range(4)))
assert sorted(status for status, _ in invoices) == [200, 200, 200, 201]
assert len({result['data']['id'] for _, result in invoices}) == 1
invoice = invoices[0][1]['data']
detail = call('GET', f'/api/v1/invoices/{invoice["id"]}')[1]['data']
listed = call('GET', f'/api/v1/customers/{customer["id"]}/invoices')[1]
balance = call('GET', f'/api/v1/customers/{customer["id"]}/balance')[1]['data']['balances']
assert listed['meta']['total'] == 1
assert len(detail['journals']) == 1
entries = detail['journals'][0]['entries']
assert len(entries) == 2 and sum(row['debit'] for row in entries) == sum(row['credit'] for row in entries) == 70
assert detail['amount'] == 70 and detail['line_items'][0]['quantity'] == 10
assert balance == [{'currency': 'USD', 'amount': 70}] and type(balance[0]['amount']) is int
assert call('POST', '/api/v1/usage_events', usage, key=key, expected=(200,))[1] == original_usage
late_status, late_body = call('POST', '/api/v1/usage_events', usage, key=key + '-late', expected=(409,))
assert late_body['error']['code'] == 'usage_period_closed'
report = {'passed': True, 'customer_id': customer['id'], 'subscription_id': subscription['id'], 'period_start': period,
          'usage_statuses': sorted(status for status, _ in usages), 'unique_usage_ids': 1,
          'invoice_statuses': sorted(status for status, _ in invoices), 'unique_invoice_ids': 1,
          'invoice_count': listed['meta']['total'], 'invoice_amount': detail['amount'], 'journal_entries': len(entries),
          'ledger_debits': sum(row['debit'] for row in entries), 'ledger_credits': sum(row['credit'] for row in entries),
          'balances': balance, 'immutable_usage_replay_after_issuance': True, 'late_usage_status': late_status}
text = json.dumps(report, indent=2) + '\n'
print(text)
