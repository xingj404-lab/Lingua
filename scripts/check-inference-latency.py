#!/usr/bin/env python3
"""Check same-input idle/repeat pairs in Lingua's numeric performance log.

Supply logs from a controlled test using the same text/options in both requests.
Token counts alone cannot establish that the source text was identical.
Exit 0: checked pairs pass; 1: regression found; 2: no eligible pairs.
"""
import argparse
import json
import sys
from collections import defaultdict

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('log')
parser.add_argument('--run-id')
parser.add_argument('--min-idle-seconds', type=float, default=300)
parser.add_argument('--max-repeat-idle-seconds', type=float, default=60)
args = parser.parse_args()
runs = defaultdict(list)
with open(args.log, encoding='utf-8') as source:
    for line in source:
        start = line.find('{')
        if start < 0:
            continue
        try:
            event = json.loads(line[start:])
        except json.JSONDecodeError:
            continue
        if event.get('event') != 'request_finished':
            continue
        if args.run_id and event.get('runID') != args.run_id:
            continue
        runs[event['runID']].append(event)

checked = failures = 0
for run_id, events in runs.items():
    events.sort(key=lambda event: event['requestNumber'])
    for cold, repeat in zip(events, events[1:]):
        if cold.get('idleSeconds', 0) < args.min_idle_seconds:
            continue
        if repeat['requestNumber'] != cold['requestNumber'] + 1:
            continue
        if cold.get('promptTokens') != repeat.get('promptTokens'):
            continue
        if cold['loadCount'] != repeat['loadCount']:
            continue
        if repeat.get('idleSeconds', 0) > args.max_repeat_idle_seconds:
            continue
        first = cold.get('firstTokenSeconds')
        next_first = repeat.get('firstTokenSeconds')
        if first is None or next_first is None:
            continue
        if next_first > 2:
            print(f'INCONCLUSIVE run={run_id}: repeat first-token wait is also slow ({next_first:.3f}s).', file=sys.stderr)
            continue
        checked += 1
        failed = first > max(2, next_first * 3)
        failures += int(failed)
        print(f"{'FAIL' if failed else 'PASS'} run={run_id} requests="
              f"{cold['requestNumber']}/{repeat['requestNumber']} "
              f"idle={cold['idleSeconds']:.1f}s first-token={first:.3f}/{next_first:.3f}s "
              f"loads={cold['loadCount']} wired={cold.get('wiredBytes', 0)}")
if not checked:
    print('No controlled idle/repeat pair available.', file=sys.stderr)
sys.exit(1 if failures else (0 if checked else 2))
