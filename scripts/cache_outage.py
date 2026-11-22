#!/usr/bin/env python3
"""Actual Redis outage check, dedicated benchmark stack only; no real Stripe traffic."""
import json
import os
import subprocess
import time
from pathlib import Path
import importlib.util

spec = importlib.util.spec_from_file_location('benchmark', Path(__file__).with_name('benchmark.py'))
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)
environment = dict(os.environ, BENCHMARK_IMAGE='ledgerly-benchmark:optimized', READ_CACHE_ENABLED='1')
compose = ['docker', 'compose', '-f', 'compose.benchmark.yaml']


def command(*args, input_text=None):
    return subprocess.run(compose + list(args), input=input_text, text=True, capture_output=True,
                          check=True, env=environment).stdout


def runner(code, marker):
    output = command('exec', '-T', 'api', 'bin/rails', 'runner', '-', input_text=code)
    return json.loads(next(line.partition('=')[2] for line in output.splitlines() if line.startswith(marker + '=')))


command('stop', 'sidekiq', 'recovery')
fixture = runner('''i=Invoice.where(status: %w[issued payment_failed]).where.missing(:stripe_payment).first!
puts 'FIXTURE='+JSON.generate({id:i.id,customer_id:i.customer_id,amount:i.amount,currency:i.currency,read_version:i.customer.read_version})
''', 'FIXTURE')
path = '/api/v1/customers/' + str(fixture['customer_id']) + '/balance'
for _ in range(20):
    status, before, headers, _ = bench.request('GET', path)
    assert status == 200
    if headers.get('x-benchmark-cache-status') == 'hit':
        break
    time.sleep(.2)
else:
    raise AssertionError('Could not warm the read cache')
old_key = f"ledgerly:reads:v1:{fixture['customer_id']}:{fixture['read_version']}:balance"
try:
    command('stop', 'benchmark-redis')
    mutation = runner('''i=Invoice.find(%d)
payload={id:"evt_cache_outage_#{i.id}",object:'event',type:'invoice.paid',livemode:false,
api_version:StripeIntegration::Settings::API_VERSION,data:{object:{id:i.stripe_invoice_id,object:'invoice'}}}
raw=JSON.generate(payload); time=Time.current
signature=Stripe::Webhook::Signature.generate_header(time,Stripe::Webhook::Signature.compute_signature(time,raw,StripeIntegration::Settings.webhook_secret!))
event=StripeIntegration::ReceiveEvent.call(raw:raw,signature:signature).record
StripeIntegration::ProcessEvent.new(event:event).call
puts 'MUTATION='+JSON.generate({event_status:event.reload.status,read_version:i.customer.reload.read_version,payment_exists:i.reload.stripe_payment.present?})
''' % fixture['id'], 'MUTATION')
    status, during, during_headers, _ = bench.request('GET', path)
    assert status == 200 and mutation['payment_exists'] and mutation['event_status'] == 'processed'
    expected = json.loads(json.dumps(before))
    for balance in expected['data']['balances']:
        if balance['currency'] == fixture['currency']:
            balance['amount'] -= fixture['amount']
    assert during == expected
finally:
    command('start', 'benchmark-redis')
for _ in range(30):
    status, after, after_headers, _ = bench.request('GET', path)
    assert status == 200 and after == expected
    if after_headers.get('x-benchmark-cache-status') == 'hit':
        break
    time.sleep(.2)
else:
    raise AssertionError('Cache did not resume after Redis restart')
old_value = command('exec', '-T', 'benchmark-redis', 'redis-cli', '--raw', 'GET', old_key).strip()
report = {'passed':True,'customer_id':fixture['customer_id'],'invoice_id':fixture['id'],
          'payment_amount':fixture['amount'],'currency':fixture['currency'],
          'old_version':fixture['read_version'],'committed_version':mutation['read_version'],
          'cached_before':before,'database_fallback_during_outage':during,'cached_after_restart':after,
          'old_cache_entry_survived_restart':bool(old_value),
          'old_cache_entry_value':json.loads(old_value) if old_value else None,
          'note':'Real Redis stopped/restarted; payment committed using read-only local provider while cache was down. Main development stack untouched.'}
assert mutation['read_version'] > fixture['read_version']
Path('.tooling/m3-optimized/cache-outage.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
