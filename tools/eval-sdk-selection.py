#!/usr/bin/env python3
"""
Scores find_sdk_function's rankings from a VERA-SDKEVAL device log against the
gold grades in entry/src/main/resources/rawfile/sdk-selection-gold.json.

Whether a function is implemented is not part of the score: a stub with grade
2 counts as found. Impl@8 is reported separately, because it is what a user
hits at runtime.

Usage (after the eval has run on the phone):
    hdc shell "hilog -x | grep VERA-SDKEVAL" > results/sdk-eval.log
    python3 tools/eval-sdk-selection.py results/sdk-eval.log
    python3 tools/eval-sdk-selection.py results/sdk-eval.log --split test
"""

import argparse
import json
import math
import re
from collections import defaultdict

GOLD = 'entry/src/main/resources/rawfile/sdk-selection-gold.json'
LINE = re.compile(r'VERA-SDKEVAL id=(\S+) path=(token|embed) bonus=(on|off) ranks=\[(.*)\]\s*$')


def parse_ranks(body):
    out = []
    for item in body.split(', '):
        item = item.strip()
        if not item:
            continue
        target, state = item.rsplit(':', 1)
        out.append((target, state == 'impl'))
    return out


def load_log(path):
    rows = {}
    for line in open(path, encoding='utf-8', errors='replace'):
        m = LINE.search(line)
        if m:
            rows[(m.group(1), m.group(2), m.group(3))] = parse_ranks(m.group(4))
    return rows


def metrics(cases, rows, path, bonus):
    scored = [c for c in cases if c['gold']]
    n = len(scored)
    recall = {1: 0, 3: 0, 8: 0}
    mrr = 0.0
    ndcg = 0.0
    impl8 = 0
    missing = []
    for c in scored:
        key = (c['id'], path, bonus)
        if key not in rows:
            missing.append(c['id'])
            continue
        ranks = [t for t, _ in rows[key]]
        gold = c['gold']
        for k in recall:
            if any(gold.get(t, 0) == 2 for t in ranks[:k]):
                recall[k] += 1
        for i, t in enumerate(ranks):
            if gold.get(t, 0) == 2:
                mrr += 1.0 / (i + 1)
                break
        dcg = sum(gold.get(t, 0) / math.log2(i + 2) for i, t in enumerate(ranks[:8]))
        ideal_grades = sorted(gold.values(), reverse=True)[:8]
        idcg = sum(g / math.log2(i + 2) for i, g in enumerate(ideal_grades))
        ndcg += dcg / idcg if idcg > 0 else 0.0
        impl = dict(rows[key])
        if any(gold.get(t, 0) >= 1 and impl.get(t, False) for t in ranks[:8]):
            impl8 += 1
    done = n - len(missing)
    if done == 0:
        return None, missing
    return {
        'n': done,
        'R@1': recall[1] / done,
        'R@3': recall[3] / done,
        'R@8': recall[8] / done,
        'MRR': mrr / done,
        'nDCG@8': ndcg / done,
        'Impl@8': impl8 / done,
    }, missing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('log')
    ap.add_argument('--gold', default=GOLD)
    ap.add_argument('--split', choices=['dev', 'test', 'all'], default='all')
    args = ap.parse_args()

    cases = json.load(open(args.gold, encoding='utf-8'))
    if args.split != 'all':
        cases = [c for c in cases if c['split'] == args.split]
    rows = load_log(args.log)

    catalogue = {f"{e['kit']}.{e['module']}.{e['name']}" for e in json.load(open('entry/src/main/resources/rawfile/sdk-index.json'))}
    for c in cases:
        for t in c['gold']:
            if t not in catalogue:
                raise SystemExit(f"gold target not in index: {c['id']} {t}")

    print(f"cases={len(cases)} with gold={sum(1 for c in cases if c['gold'])} log rows={len(rows)}")
    print()
    print('| path | bonus | n | R@1 | R@3 | R@8 | MRR | nDCG@8 | Impl@8 |')
    print('|---|---|---|---|---|---|---|---|---|')
    for path in ['token', 'embed']:
        for bonus in ['on', 'off']:
            m, missing = metrics(cases, rows, path, bonus)
            if m is None:
                print(f'| {path} | {bonus} | 0 | - | - | - | - | - | - |')
                continue
            print(f"| {path} | {bonus} | {m['n']} | {m['R@1']:.2f} | {m['R@3']:.2f} | {m['R@8']:.2f} | "
                  f"{m['MRR']:.2f} | {m['nDCG@8']:.2f} | {m['Impl@8']:.2f} |")
            if missing:
                print(f'  missing from log: {", ".join(missing)}')
    print()
    print('Cases whose rank differs between bonus on and off (token path):')
    for c in cases:
        a = rows.get((c['id'], 'token', 'on'))
        b = rows.get((c['id'], 'token', 'off'))
        if a is not None and b is not None and [t for t, _ in a] != [t for t, _ in b]:
            print(f"  {c['id']} {c['need']!r}")


if __name__ == '__main__':
    main()
