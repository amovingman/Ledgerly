import argparse,json,subprocess,time,datetime
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',required=True);p.add_argument('--until',required=True);p.add_argument('--seconds',type=int,default=450);p.add_argument('--workers',type=int,default=1);a=p.parse_args()
# One persistent shell per container, not hundreds of Docker CLI startups.
processes=[]
for name in ['api','benchmark-postgres','benchmark-provider','benchmark-redis'] + ['sidekiq'+('-'+str(i) if i>1 else '') for i in range(1,a.workers+1)]:
 path=Path(a.output+'-'+name+'.txt');stream=path.open('w')
 script='i=0; while [ "$i" -lt '+str(a.seconds)+' ]; do date -u +%s; cat /sys/fs/cgroup/cpu.stat; cat /sys/fs/cgroup/cpu.pressure; cat /sys/fs/cgroup/io.pressure; cat /proc/pressure/cpu; sleep 1; i=$((i+1)); done'
 container = 'ledgerly-benchmark-sidekiq-'+name.split('-')[-1] if name.startswith('sidekiq-') else 'ledgerly-benchmark-'+name+'-1'
 processes.append((subprocess.Popen(['docker','exec',container,'sh','-c',script],stdout=stream,stderr=stream),stream))
try:
 end=time.monotonic()+a.seconds
 while time.monotonic()<end and not Path(a.until).exists():time.sleep(1)
finally:
 for proc,stream in processes:proc.terminate();proc.wait();stream.close()
