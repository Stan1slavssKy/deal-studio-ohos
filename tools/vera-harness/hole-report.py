#!/usr/bin/env python3
"""What the agent's written holes were, grouped: the needs that recur across requests are the blocks the catalogue lacks.

    python3 tools/vera-harness/hole-report.py PATH [PATH ...] [--min N] [--code]

Each PATH is a directory searched for holes.jsonl (written by tools/vera-harness/agent-run.js) and trace.jsonl (pulled
off the phone: its "hole" events, agent/AgentAppHost.ets), or one such file. Prints, as Markdown: how the holes ended,
then each group of needs seen in at least --min requests (default 2), most frequent first, with how they ended and an
example request. --code adds the shortest written section of each group, the first draft of the block it could become.

Needs are grouped by their words: lowercased, the moment in parentheses and filler words dropped, two needs in one group
when they share at least half their words. That is rough on purpose; a group is a candidate, read before it is built.
"""
import argparse
import json
import os
import re
import statistics
import sys

FILLER = set('a an the and or of to for in on at by with from is are be it its this that each every as into than then '
             'there their them they person app phone screen shows show what when which who how one two all any so it\'s '
             'figure section request asks lets'.split())


def words(need):
    text = re.sub(r'\([^)]*\)', ' ', need.lower())
    text = re.sub(r'\bthe figure\b', ' ', text)
    return {w for w in re.findall(r"[a-z][a-z'-]+", text) if w not in FILLER and len(w) > 2}


def records(paths):
    for path in paths:
        files = []
        if os.path.isdir(path):
            for root, _dirs, names in os.walk(path):
                files += [os.path.join(root, n) for n in names if n in ('holes.jsonl', 'trace.jsonl')]
        else:
            files.append(path)
        for f in files:
            label = os.path.basename(os.path.dirname(f))
            for line in open(f, encoding='utf-8'):
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if f.endswith('trace.jsonl'):
                    if r.get('event') != 'hole':
                        continue
                r.setdefault('label', label)
                yield r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('paths', nargs='+')
    ap.add_argument('--min', type=int, default=2)
    ap.add_argument('--code', action='store_true')
    args = ap.parse_args()
    holes = list(records(args.paths))
    if not holes:
        sys.exit('no holes found under ' + ' '.join(args.paths))

    outcomes = {}
    for h in holes:
        outcomes.setdefault(h.get('outcome', '?'), []).append(h.get('ms', 0) / 1000)
    print('# Written holes: %d, in %d requests\n' % (len(holes), len({h['label'] for h in holes})))
    print('| outcome | holes | median s | thinking used |')
    print('|---|---|---|---|')
    for k, ms in sorted(outcomes.items(), key=lambda x: -len(x[1])):
        thought = sum(1 for h in holes if h.get('outcome') == k and h.get('thought'))
        print('| %s | %d | %.1f | %d |' % (k, len(ms), statistics.median(ms), thought))
    print()

    # One entry per need, then greedy grouping by shared words.
    needs = []
    for h in holes:
        for i, need in enumerate(h.get('needs', [])):
            needs.append({'need': need, 'words': words(need), 'phone': (h.get('phone') or [False] * 99)[i],
                          'hole': h, 'missed': need in (h.get('missed') or [])})
    groups = []
    for n in needs:
        for g in groups:
            union = g['words'] | n['words']
            if union and len(g['words'] & n['words']) / len(union) >= 0.5:
                g['items'].append(n)
                break
        else:
            groups.append({'words': n['words'], 'items': [n]})
    recurring = [g for g in groups if len({i['hole']['label'] for i in g['items']}) >= args.min]
    recurring.sort(key=lambda g: -len({i['hole']['label'] for i in g['items']}))

    print('# Needs written in at least %d requests: %d groups\n' % (args.min, len(recurring)))
    print('| requests | phone | written | partial / missed | reported | example need | example request |')
    print('|---|---|---|---|---|---|---|')
    for g in recurring:
        items = g['items']
        labels = {i['hole']['label'] for i in items}
        ended = lambda o: sum(1 for i in items if i['hole'].get('outcome') == o)
        first = items[0]
        print('| %d | %s | %d | %d / %d | %d | %s | %s |' % (
            len(labels), 'yes' if any(i['phone'] for i in items) else '', ended('written'),
            ended('partial'), sum(1 for i in items if i['missed']), ended('reported') + ended('known'),
            first['need'][:90].replace('|', '/'), first['hole'].get('prompt', '')[:60].replace('|', '/')))
    if args.code:
        for g in recurring:
            done = [i['hole'] for i in g['items'] if i['hole'].get('code')]
            if not done:
                continue
            shortest = min(done, key=lambda h: len(h['code']))
            print('\n## %s\n\n```\n%s\n```' % (g['items'][0]['need'][:100], shortest['code'].strip()))


if __name__ == '__main__':
    main()
