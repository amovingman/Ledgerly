import hashlib, hmac, json, subprocess, time
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from uuid import uuid4
key=next(line.partition('=')[2].strip() for line in Path('.tooling/m2-verify.env').read_text().splitlines() if line.startswith('API_KEY='))
secret='whsec_localverification'
base='http://127.0.0.1:3001'
compose=['docker','compose','-p','ledgerly-m2-verify','--env-file','.tooling/m2-verify.env']

def event():
    return {'id':'evt_'+uuid4().hex,'object':'event','api_version':'2026-11-18.endive','type':'customer.updated',
            'livemode':False,'created':int(time.time()),'data':{'object':{'id':'cus_localfixture','object':'customer'}}}

def deliver(payload, invalid=False):
    raw=json.dumps(payload,indent=2).encode()
    stamp=int(time.time())
    digest=hmac.new(secret.encode(), str(stamp).encode()+b'.'+raw,hashlib.sha256).hexdigest()
    signature=f't={stamp},v1={digest}' if not invalid else f't={stamp},v1=invalid'
    req=Request(base+'/webhooks/stripe',data=raw,headers={'Content-Type':'application/json','Stripe-Signature':signature})
    try: res=urlopen(req,timeout=15)
    except HTTPError as error:res=error
    return res.status,json.load(res)

def status(identity):
    req=Request(base+'/api/v1/stripe_events/'+identity,headers={'Authorization':'Bearer '+key})
    return json.load(urlopen(req,timeout=10))['data']

def wait_done(identity):
    deadline=time.monotonic()+60
    while time.monotonic()<deadline:
        current=status(identity)
        if current['status']=='ignored':return current
        time.sleep(1)
    raise AssertionError('Worker did not finish: '+json.dumps(current))

first=event()
code,_=deliver(first)
assert code==200
processed=wait_done(first['id'])
code,replay=deliver(first)
assert code==200 and replay['duplicate'] is True
invalid,_=deliver(event(),invalid=True)
assert invalid==400
try:
    subprocess.run(compose+['stop','redis'],check=True,capture_output=True)
    second=event()
    outage_code,_=deliver(second)
    assert outage_code==200
    pending=status(second['id'])
    assert pending['status']=='received'
finally:
    subprocess.run(compose+['start','redis'],check=True,capture_output=True)
recovered=wait_done(second['id'])
report={'passed':True,'initial_event':first['id'],'initial_processing_status':processed['status'],
        'duplicate_receipt_acknowledged':replay['duplicate'],'bad_signature_status':invalid,
        'queue_outage_event':second['id'],'queue_outage_http_status':outage_code,
        'status_while_queue_down':pending['status'],'status_after_restart_and_sweep':recovered['status'],
        'attempts_after_recovery':recovered['attempts'],'provider_api_calls_required':False}
print(json.dumps(report,indent=2))
