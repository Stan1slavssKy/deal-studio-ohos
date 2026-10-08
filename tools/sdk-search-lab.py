#!/usr/bin/env python3
"""
Host-side stand for the embedding half of find_sdk_function: ranks the gold
queries against several ways of writing an entry's text, with no phone.

It does what the app does -- embed the query as plain text with the same model
(mean pooling, L2-normalised) and rank the corpus by dot product -- so a number
here is the number the phone would give for the same corpus vectors. Nothing is
ranked by whether a target has an adapter: that is not a relevance signal here.

Variants (the text that gets embedded for each entry):
  desc     kit module name description                     what the app shipped with
  summary  kit module name summary                         falls back to description if none
  both     kit module name description summary

Corpus vectors are cached per variant in --cache-dir, so a rerun is seconds.
The `desc` variant can reuse the bundled cache from git when it was built from
exactly that text (--desc-bin).

Usage:
    python3 tools/sdk-search-lab.py --summaries /tmp/sdk-summaries.json \\
        --model ~/embeddinggemma-300m-q4_k_m.gguf \\
        --llama-embedding entry/src/main/cpp/llama.cpp/build-host/bin/llama-embedding \\
        --cache-dir /tmp/sdk-lab --variants desc,summary,both
"""

import argparse
import importlib.util
import json
import math
import struct
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('bse', HERE / 'build-sdk-embeddings.py')
bse = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bse)


def text_for(e, variant, summaries):
    key = f"{e['kit']}.{e['module']}.{e['name']}"
    desc = e.get('description') or ''
    summ = summaries.get(key, '')
    if variant == 'desc':
        body = desc
    elif variant == 'summary':
        body = summ or desc
    elif variant == 'both':
        body = ' '.join(p for p in (desc, summ) if p)
    else:
        raise SystemExit(f'unknown variant {variant}')
    parts = [e['kit'], e['module'], e['name'], body]
    return ' '.join(p for p in parts if p).replace('\n', ' ').replace('\r', ' ')


def load_bin(path):
    raw = path.read_bytes()
    magic, version, count, dim, _, _ = struct.unpack('<6I', raw[:24])
    return np.frombuffer(raw, dtype='<f4', offset=24).reshape(count, dim)


def corpus_vectors(variant, entries, summaries, args):
    args.cache_dir.mkdir(parents=True, exist_ok=True)
    cache = args.cache_dir / f'{variant}.npy'
    if cache.exists():
        v = np.load(cache)
        if v.shape[0] == len(entries):
            return v
    if variant == 'desc' and args.desc_bin:
        v = load_bin(args.desc_bin)
        if v.shape[0] == len(entries):
            np.save(cache, v)
            return v
    texts = [text_for(e, variant, summaries) for e in entries]
    out = []
    started = time.time()
    for i in range(0, len(texts), args.chunk_size):
        out += bse.embed_chunk(args.llama_embedding, args.model, texts[i:i + args.chunk_size], args.threads)
        print(f'  {variant}: {min(i + args.chunk_size, len(texts))}/{len(texts)} '
              f'({time.time() - started:.0f}s)', file=sys.stderr)
    v = np.array(out, dtype=np.float32)
    args.cache_dir.mkdir(parents=True, exist_ok=True)
    np.save(cache, v)
    return v


def metrics(cases, ranks):
    """ranks: id -> list of targets (best first, duplicates kept, as the app returns them)."""
    scored = [c for c in cases if c['gold']]
    n = len(scored)
    r = {1: 0, 3: 0, 8: 0}
    any8 = 0
    mrr = ndcg = 0.0
    for c in scored:
        t = ranks[c['id']]
        g = c['gold']
        for k in r:
            if any(g.get(x, 0) == 2 for x in t[:k]):
                r[k] += 1
        if any(g.get(x, 0) >= 1 for x in t[:8]):
            any8 += 1
        for i, x in enumerate(t):
            if g.get(x, 0) == 2:
                mrr += 1 / (i + 1)
                break
        dcg = sum(g.get(x, 0) / math.log2(i + 2) for i, x in enumerate(t[:8]))
        ideal = sorted(g.values(), reverse=True)[:8]
        idcg = sum(v / math.log2(i + 2) for i, v in enumerate(ideal))
        ndcg += dcg / idcg if idcg else 0
    return n, r[1] / n, r[3] / n, r[8] / n, any8 / n, mrr / n, ndcg / n


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--index', default=HERE.parent / 'entry/src/main/resources/rawfile/sdk-index.json', type=Path)
    ap.add_argument('--summaries', required=True, type=Path)
    ap.add_argument('--gold', default=HERE.parent / 'entry/src/main/resources/rawfile/sdk-selection-gold.json', type=Path)
    ap.add_argument('--model', required=True, type=Path)
    ap.add_argument('--llama-embedding', required=True, type=Path)
    ap.add_argument('--cache-dir', required=True, type=Path)
    ap.add_argument('--variants', default='desc,summary,both')
    ap.add_argument('--desc-bin', type=Path, help='a cache built from the `desc` text, to skip re-embedding it')
    ap.add_argument('--chunk-size', default=2000, type=int)
    ap.add_argument('--threads', default=12, type=int)
    ap.add_argument('--public-only', action='store_true',
                    help='rank only entries that are not @systemapi: those got no summary, so mixing them in favours the summary variants')
    ap.add_argument('--show', default='a01,a02,b10b', help='case ids whose top-8 to print per variant')
    args = ap.parse_args()

    entries = json.loads(args.index.read_text())
    summaries = json.loads(args.summaries.read_text())
    cases = json.loads(args.gold.read_text())
    keys = [f"{e['kit']}.{e['module']}.{e['name']}" for e in entries]
    print(f'{len(entries)} entries, {len(summaries)} summaries '
          f'({sum(1 for k in set(keys) if k in summaries)} unique keys covered), {len(cases)} cases', file=sys.stderr)

    qv = np.array(bse.embed_chunk(args.llama_embedding, args.model, [c['need'] for c in cases], args.threads),
                  dtype=np.float32)

    print('\n| variant | n | R@1 | R@3 | R@8 | any gold@8 | MRR | nDCG@8 |\n|---|--:|--:|--:|--:|--:|--:|--:|')
    shown = {}
    for variant in args.variants.split(','):
        vecs = corpus_vectors(variant, entries, summaries, args)
        scores = qv @ vecs.T
        if args.public_only:
            scores[:, [bool(e.get('systemapi')) for e in entries]] = -9
        ranks = {}
        for i, c in enumerate(cases):
            top = np.argsort(-scores[i])[:50]
            ranks[c['id']] = [keys[j] for j in top]
        n, r1, r3, r8, a8, mrr, ndcg = metrics(cases, ranks)
        print(f'| {variant} | {n} | {r1:.2f} | {r3:.2f} | {r8:.2f} | {a8:.2f} | {mrr:.2f} | {ndcg:.2f} |')
        shown[variant] = ranks

    for cid in [x for x in args.show.split(',') if x]:
        case = next((c for c in cases if c['id'] == cid), None)
        if not case:
            continue
        print(f"\n[{cid}] {case['need']}   gold={case['gold']}")
        for variant, ranks in shown.items():
            top = ranks[cid]
            pos = {t: top.index(t) + 1 for t in case['gold'] if t in top}
            print(f'  {variant:8} gold positions in top-50: {pos or "none"}')
            print('           ' + ', '.join(t.split('.', 1)[1] for t in top[:8]))


if __name__ == '__main__':
    sys.exit(main())
