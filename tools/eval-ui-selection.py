#!/usr/bin/env python3
"""
Host-side recall of the UI component selector, against docs/ui-gold.json.

Embeds the optional std/ui components (the same text the app embeds:
VeraUiCatalog.componentEmbeddingText) and the gold prompts with the same
EmbeddingGemma GGUF the app uses, then reports R@k -- the share of the
components a prompt really needs that appear in the top k of the ranking.

Two queries are compared:
  prompt  the whole user prompt embedded as one query (no LLM involved)
  needs   the phrases the extraction model produced for the prompt, one query
          each, ranked by the best score over the phrases (give them with
          --needs, a JSON object id -> [phrase, ...], e.g. taken from the
          device's VERA-UI-NEEDS log lines)

The selection actually sent to the model is also scored: the union of the
top two components per phrase, then the closure the app applies (Canvas with
Path, Grid with Cell, Timeline with TimelineItem, KeyValueGroup with
KeyValueItem). That is the number that decides whether the model is shown the
component it needs.

    python3 tools/eval-ui-selection.py --components components.json \
        --model embeddinggemma-300m-q4_k_m.gguf \
        --llama-embedding entry/src/main/cpp/llama.cpp/build-host/bin/llama-embedding
"""

import argparse
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

KS = [1, 3, 5, 8, 16]
COMPANIONS = [('Canvas', 'Path'), ('Grid', 'Cell'), ('Timeline', 'TimelineItem'),
              ('KeyValueGroup', 'KeyValueItem')]
PER_PHRASE = 2


def embed(llama: Path, model: Path, texts: list, threads: int) -> list:
    one_line = [' '.join(t.split()) for t in texts]
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False, encoding='utf-8') as f:
        f.write('\n'.join(one_line))
        path = f.name
    try:
        r = subprocess.run([str(llama), '-m', str(model), '-f', path, '--pooling', 'mean',
                            '--embd-normalize', '2', '--embd-output-format', 'array',
                            '-t', str(threads)], capture_output=True, text=True, check=True)
    finally:
        Path(path).unlink(missing_ok=True)
    for line in r.stdout.splitlines():
        line = line.strip()
        if line.startswith('['):
            vecs = json.loads(line)
            if len(vecs) != len(texts):
                raise RuntimeError(f'{len(vecs)} vectors for {len(texts)} texts')
            return vecs
    raise RuntimeError('no array in llama-embedding output:\n' + r.stdout[-1500:])


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def close(selected: set) -> set:
    out = set(selected)
    for a, b in COMPANIONS:
        if a in out or b in out:
            out.add(a)
            out.add(b)
    return out


def rank(names, comp_vecs, qvec):
    scored = sorted(((dot(qvec, v), n) for n, v in zip(names, comp_vecs)), reverse=True)
    return [n for _, n in scored]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--components', required=True, type=Path)
    ap.add_argument('--gold', default=Path('docs/ui-gold.json'), type=Path)
    ap.add_argument('--model', required=True, type=Path)
    ap.add_argument('--llama-embedding', required=True, type=Path)
    ap.add_argument('--needs', type=Path, help='JSON: gold id -> list of extracted phrases')
    ap.add_argument('--threads', default=8, type=int)
    ap.add_argument('--verbose', action='store_true')
    args = ap.parse_args()

    comps = json.loads(args.components.read_text())['optional']
    names = [c['name'] for c in comps]
    gold = json.loads(args.gold.read_text())
    needs = json.loads(args.needs.read_text()) if args.needs else {}

    texts = [c['text'] for c in comps] + [g['prompt'] for g in gold]
    phrase_index = []
    for g in gold:
        for p in needs.get(g['id'], []):
            phrase_index.append((g['id'], p))
    texts += [p for _, p in phrase_index]
    vecs = embed(args.llama_embedding, args.model, texts, args.threads)
    comp_vecs = vecs[:len(comps)]
    prompt_vecs = vecs[len(comps):len(comps) + len(gold)]
    phrase_vecs = vecs[len(comps) + len(gold):]
    by_id = {}
    for (gid, _), v in zip(phrase_index, phrase_vecs):
        by_id.setdefault(gid, []).append(v)

    with_gold = [(g, pv) for g, pv in zip(gold, prompt_vecs) if g['gold']]
    n_opt = len(names)
    print(f'{len(gold)} prompts, {len(with_gold)} with gold components, {n_opt} optional components')

    def recall_table(label, ranking_for):
        print(f'\n{label}')
        print('  k    recall   all-found   random')
        for k in KS:
            rec = []
            hit = 0
            for g, pv in with_gold:
                top = ranking_for(g, pv)[:k]
                found = [x for x in g['gold'] if x in top]
                rec.append(len(found) / len(g['gold']))
                hit += len(found) == len(g['gold'])
            print(f'  {k:<4} {100 * sum(rec) / len(rec):5.1f}%   {100 * hit / len(with_gold):5.1f}%'
                  f'     {100 * min(1.0, k / n_opt):5.1f}%')

    recall_table('R@k, whole prompt as one query:',
                 lambda g, pv: rank(names, comp_vecs, pv))

    if needs:
        have = [(g, pv) for g, pv in with_gold if g['id'] in by_id]
        print(f'\n{len(have)} gold prompts have extracted phrases')

        def need_ranking(g, pv):
            best = {n: -9.0 for n in names}
            for qv in by_id[g['id']]:
                for n, v in zip(names, comp_vecs):
                    s = dot(qv, v)
                    if s > best[n]:
                        best[n] = s
            return [n for n, _ in sorted(best.items(), key=lambda kv: -kv[1])]

        with_gold_saved = with_gold
        with_gold = have
        recall_table('R@k, best score over the extracted phrases:', need_ranking)

        # What the app really sends: top PER_PHRASE per phrase, then the closure.
        found_all = 0
        found_frac = []
        sizes = []
        misses = []
        for g, pv in have:
            picked = set()
            for qv in by_id[g['id']]:
                picked.update(rank(names, comp_vecs, qv)[:PER_PHRASE])
            sel = close(picked)
            sizes.append(len(sel))
            hit = [x for x in g['gold'] if x in sel]
            found_frac.append(len(hit) / len(g['gold']))
            found_all += len(hit) == len(g['gold'])
            if len(hit) < len(g['gold']):
                misses.append((g['id'], [x for x in g['gold'] if x not in sel]))
        print(f'\nSelection as the app sends it (top {PER_PHRASE} per phrase + closure):')
        print(f'  component recall  {100 * sum(found_frac) / len(found_frac):.1f}%')
        print(f'  all needed shown  {100 * found_all / len(have):.1f}%  of {len(have)} prompts')
        print(f'  optional shown    {sum(sizes) / len(sizes):.1f} of {n_opt} on average')
        for gid, missing in misses:
            print(f'  missed {gid}: {", ".join(missing)}')
        with_gold = with_gold_saved

    # The alternative to extracting phrases: embed the whole prompt and keep the
    # K best components, then the same closure.
    print('\nSelection from the whole prompt (top K + closure):')
    print('  K    component recall   all needed shown   optional shown')
    for K in [3, 4, 5, 6, 8]:
        fr = []
        allf = 0
        sizes = []
        for g, pv in with_gold:
            sel = close(set(rank(names, comp_vecs, pv)[:K]))
            sizes.append(len(sel))
            hit = [x for x in g['gold'] if x in sel]
            fr.append(len(hit) / len(g['gold']))
            allf += len(hit) == len(g['gold'])
        print(f'  {K:<4} {100 * sum(fr) / len(fr):10.1f}%      {100 * allf / len(with_gold):10.1f}%'
              f'        {sum(sizes) / len(sizes):5.1f} of {n_opt}')

    if args.verbose:
        print()
        for g, pv in with_gold:
            print(f"{g['id']:<12} gold={g['gold']} prompt-top5={rank(names, comp_vecs, pv)[:5]}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
