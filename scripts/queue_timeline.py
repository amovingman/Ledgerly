#!/usr/bin/env python3
"""Reconstruct outstanding receipts between samples, using stored event timestamps."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', required=True)
    parser.add_argument('--directory', required=True)
    args = parser.parse_args()
    output = Path(args.directory)
    since = int(json.loads((output/'observation-boundary.json').read_text())['since'])
    ruby = '''sql = <<~SQL
WITH changes AS (
 SELECT created_at AS at,1 AS delta FROM stripe_events WHERE id>%s
 UNION ALL
 SELECT processed_at AS at,-1 AS delta FROM stripe_events WHERE id>%s AND processed_at IS NOT NULL
), points AS (SELECT at,sum(delta) AS delta FROM changes GROUP BY at),
levels AS (SELECT at,sum(delta) OVER (ORDER BY at) AS pending FROM points)
SELECT to_char(at, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS at,pending::bigint AS pending
FROM levels ORDER BY pending DESC,at LIMIT 20
SQL
puts 'TIMELINE='+JSON.generate(ApplicationRecord.connection.select_all(sql).to_a)
''' % (since, since)
    result = subprocess.run(['docker','compose','-f','compose.benchmark.yaml','exec','-T','api','bin/rails','runner','-'],
                            input=ruby,text=True,capture_output=True,check=True,
                            env=dict(os.environ,BENCHMARK_IMAGE=args.image))
    rows = json.loads(next(line.partition('=')[2] for line in result.stdout.splitlines() if line.startswith('TIMELINE=')))
    report = {'peak_pending':int(rows[0]['pending']) if rows else 0,'highest_points':rows,
              'scope':'All accepted timed event lifetimes, including drain; timestamp estimate, not commit order. Receipt timestamps precede receipt commit; processed timestamps precede processing commit.'}
    (output/'queue-timeline.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'timestamp_pending_peak':report['peak_pending']}))


if __name__ == '__main__':
    main()
