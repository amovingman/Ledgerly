import argparse,datetime,gzip,json
from pathlib import Path

def counters(path):
 records=[];row=None;pressure=0
 for line in path.read_text().splitlines():
  bits=line.split()
  if not bits:continue
  if bits[0].isdigit():
   if row:records.append(row)
   row={'at':int(bits[0])};pressure=0
  elif row is not None and bits[0] in ['some','full']:
   if bits[0]=='some':pressure+=1
   key=['cpu','io','vm'][pressure-1]+'_'+bits[0]
   row[key]=int(next(v.partition('=')[2] for v in bits if v.startswith('total=')))
  elif row is not None and len(bits)==2:row[bits[0]]=int(bits[1])
 if row:records.append(row)
 result=[]
 for old,new in zip(records,records[1:]):
  dt=new['at']-old['at']
  if not dt:continue
  result.append({'at':new['at'],'cpu_pct':round((new['usage_usec']-old['usage_usec'])/dt/10000,1),'throttled_periods':new['nr_throttled']-old['nr_throttled'],'throttled_ms':round((new['throttled_usec']-old['throttled_usec'])/1000,1),'cpu_pressure_ms':round((new['cpu_some']-old['cpu_some'])/1000,1),'io_pressure_ms':round((new['io_some']-old['io_some'])/1000,1),'vm_cpu_pressure_ms':round((new['vm_some']-old['vm_some'])/1000,1)})
 return result

if __name__ == '__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--directory',default=str(Path(__file__).parent));parser.add_argument('--prefix',default='before-cgroup');parser.add_argument('--jobs',nargs='+',default=['before-slow-jobs.ndjson']);args=parser.parse_args()
 root=Path(args.directory);jobs=[]
 for name in args.jobs:
  path=root/name
  if not path.exists():path=path.with_suffix(path.suffix+'.gz')
  raw=gzip.decompress(path.read_bytes()) if path.suffix=='.gz' else path.read_bytes()
  jobs.extend(json.loads(line) for line in raw.splitlines())
 peak=max(jobs,key=lambda row:row['wall_ms'])
 stamp=datetime.datetime.fromisoformat(peak['finished_at'].replace('Z','+00:00')).timestamp()
 report={'slow_jobs_at_least_100ms':len(jobs),'slowest_job':peak,'counters_around_slowest':{}}
 for path in sorted(root.glob(args.prefix+'-*.txt')):
  rows=counters(path)
  report['counters_around_slowest'][path.name]=[row for row in rows if stamp-4<=row['at']<=stamp+3]
 print(json.dumps(report,indent=2))
