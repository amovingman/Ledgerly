#!/usr/bin/env python3
"""Keep the original load gate and reject between-sample pending spikes too."""
import argparse
import json
from pathlib import Path


def assess(summary, timeline):
    requirements = {
        'original_sustained_gate': summary['passed'] is True,
        'sampled_pending_under_100': summary['peak_received'] < 100,
        'timestamp_pending_under_100': timeline['peak_pending'] < 100,
    }
    return {'passed': all(requirements.values()), 'requirements': requirements,
            'sampled_pending_peak': summary['peak_received'],
            'timestamp_pending_peak': timeline['peak_pending'], 'strict_peak_limit': 100}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', required=True)
    directory = Path(parser.parse_args().directory)
    report = assess(json.loads((directory/'summary.json').read_text()),
                    json.loads((directory/'queue-timeline.json').read_text()))
    (directory/'queue-acceptance.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
