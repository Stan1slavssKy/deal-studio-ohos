#!/usr/bin/env python3
"""
Recall of the embedding search over a gold file, on the host, with the vectors
the app ships (or any other cache with the same layout).

For every case the query is embedded with the same model the phone uses (mean
pooling, L2-normalised), the corpus is ranked by dot product, and the first
`k` distinct functions are looked at. A case counts as a hit at k when one of
its grade-2 targets is among them. Nothing is ranked by whether a target has an
adapter.

Gold files are lists of {id, need, gold: {"Kit.module.name": grade}}.

Usage:
    python3 tools/sdk-gold-host.py --gold docs/prompts/sdk-gold-50.json \\
        --model ~/embeddinggemma-300m-q4_k_m.gguf \\
        --llama-embedding entry/src/main/cpp/llama.cpp/build-host/bin/llama-embedding

    # the same for an older corpus: its index, its vectors; copies of one function
    # (promise and callback forms) are collapsed to the best-ranked one
    ... --index old-index.json --vectors old.bin
"""

import argparse
import importlib.util
import json
import struct
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('bse', HERE / 'build-sdk-embeddings.py')
bse = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bse)

KS = (1, 3, 8, 16, 32)


def load_vectors(path):
    if str(path).endswith('.npy'):
        return np.load(path)
    raw = path.read_bytes()
    _, _, count, dim, _, _ = struct.unpack('<6I', raw[:24])
    return np.frombuffer(raw, dtype='<f4', offset=24).reshape(count, dim)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--gold', required=True, type=Path)
    ap.add_argument('--index', default=HERE.parent / 'entry/src/main/resources/rawfile/sdk-index.json', type=Path)
    ap.add_argument('--vectors', default=HERE.parent / 'entry/src/main/resources/rawfile/sdk-embeddings.bin', type=Path)
    ap.add_argument('--model', required=True, type=Path)
    ap.add_argument('--llama-embedding', required=True, type=Path)
    ap.add_argument('--threads', default=12, type=int)
    ap.add_argument('--misses', type=int, default=16, help='list cases with no grade-2 hit within this k')
    ap.add_argument('--json-out', type=Path, help='write per-case ranks here')
    args = ap.parse_args()

    entries = json.loads(args.index.read_text())
    keys = [f"{e['kit']}.{e['module']}.{e['name']}" for e in entries]
    vecs = load_vectors(args.vectors)
    if vecs.shape[0] != len(entries):
        sys.exit(f'{vecs.shape[0]} vectors for {len(entries)} index entries: not the same corpus')
    cases = json.loads(args.gold.read_text())
    qv = np.array(bse.embed_chunk(args.llama_embedding, args.model, [c['need'] for c in cases], args.threads),
                  dtype=np.float32)
    scores = qv @ vecs.T

    ranks = {}
    for i, c in enumerate(cases):
        seen, out = set(), []
        for j in np.argsort(-scores[i])[:600]:
            if keys[j] in seen:
                continue
            seen.add(keys[j])
            out.append(keys[j])
            if len(out) >= max(KS):
                break
        ranks[c['id']] = out

    def first_hit(c):
        for pos, t in enumerate(ranks[c['id']], 1):
            if c['gold'].get(t, 0) == 2:
                return pos
        return None

    hits = {c['id']: first_hit(c) for c in cases}
    n = len(cases)
    print(f'{n} cases, {len(entries)} index entries, vectors {args.vectors.name}\n')
    print('| k | cases hit | R@k |\n|--:|--:|--:|')
    for k in KS:
        h = sum(1 for v in hits.values() if v is not None and v <= k)
        print(f'| {k} | {h} | {h / n:.2f} |')
    mrr = sum(1 / v for v in hits.values() if v) / n
    print(f'\nMRR {mrr:.2f}')

    miss = [c for c in cases if not (hits[c['id']] and hits[c['id']] <= args.misses)]
    if miss:
        print(f'\nno grade-2 target within top {args.misses} ({len(miss)}):')
        for c in miss:
            pos = hits[c['id']]
            print(f"  {c['id']} \"{c['need']}\"  first hit: {pos if pos else f'>{max(KS)}'}")
            print('      want:', ', '.join(k.split('.', 1)[1] for k, g in c['gold'].items() if g == 2))
            print('      got :', ', '.join(t.split('.', 1)[1] for t in ranks[c['id']][:5]))
    if args.json_out:
        args.json_out.write_text(json.dumps({'hits': hits, 'ranks': ranks}, indent=1))


if __name__ == '__main__':
    sys.exit(main())
