#!/usr/bin/env python3
"""
Precomputes EmbeddingGemma vectors for every entry in entry/src/main/
resources/rawfile/celia-intent-index.json, host-side, and writes them in the
exact binary format VeraCeliaIntentEmbeddingCache.ets expects -- the celia
corpus doesn't vary per device (unlike the old per-device intent-embeddings.
json), so, like the SDK surface, it should embed once, offline, rather than
pay the on-device cost per install.

This is a structural copy of tools/build-sdk-embeddings.py -- same binary
layout, same hash functions, same llama-embedding CLI invocation, same GGUF
-- adapted only for celia-intent-index.json's own identity key
(bundle/intentName instead of kit.module.name) and embedding text (name +
description instead of kit module name + summary).

Usage:
    python3 tools/build-celia-intent-embeddings.py \
        --model ~/path/to/embeddinggemma-300m-Q4_K_M.gguf \
        --llama-embedding entry/src/main/cpp/llama.cpp/build-host/bin/llama-embedding
"""

import argparse
import json
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

MAGIC = 0x56434931  # 'VCI1' -- must match VeraCeliaIntentEmbeddingCache.ets's MAGIC
FORMAT_VERSION = 1  # must match FORMAT_VERSION there
MODEL_FILE = 'embeddinggemma-300m-q4_k_m.gguf'  # must match VeraEmbeddings.MODEL_FILE


def fnv1a(s: str, seed: int) -> int:
    h = seed
    for ch in s:
        h = (h ^ ord(ch)) & 0xFFFFFFFF
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def source_hash(entries: list) -> int:
    h = 0x811c9dc5
    for e in entries:
        key = f"{e['bundle']}/{e['intentName']}"
        h = fnv1a(key, h)
    return h


def model_hash() -> int:
    return fnv1a(MODEL_FILE, 0x811c9dc5)


def embedding_text(e: dict) -> str:
    # Must match VeraCeliaIntentEmbeddingCache.ets's own embedding-text
    # function exactly -- a different text here embeds a different thing
    # than the live on-device path would for the same entry, silently.
    parts = [e['bundle'], e['intentName'], e['name'], e.get('description') or '']
    text = ' '.join(p for p in parts if p)
    return text.replace('\n', ' ').replace('\r', ' ')


def embed_chunk(llama_embedding: Path, model: Path, texts: list, threads: int) -> list:
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False, encoding='utf-8') as f:
        f.write('\n'.join(texts))
        prompt_file = f.name
    try:
        result = subprocess.run(
            [str(llama_embedding), '-m', str(model), '-f', prompt_file,
             '--pooling', 'mean', '--embd-normalize', '2',
             '--embd-output-format', 'array', '-t', str(threads)],
            capture_output=True, text=True, check=True)
    finally:
        Path(prompt_file).unlink(missing_ok=True)
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.startswith('['):
            vecs = json.loads(line)
            if len(vecs) != len(texts):
                raise RuntimeError(f'embedded {len(vecs)} vectors for {len(texts)} texts')
            return vecs
    raise RuntimeError('no array output found in llama-embedding stdout:\n' + result.stdout[-2000:] +
                        '\n--- stderr ---\n' + result.stderr[-2000:])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--model', required=True, type=Path, help='EmbeddingGemma GGUF path')
    ap.add_argument('--llama-embedding', required=True, type=Path,
                     help='host build of the llama-embedding CLI')
    ap.add_argument('--celia-index', default=Path('entry/src/main/resources/rawfile/celia-intent-index.json'),
                     type=Path)
    ap.add_argument('--out', default=Path('entry/src/main/resources/rawfile/celia-intent-embeddings.bin'),
                     type=Path)
    ap.add_argument('--chunk-size', default=2000, type=int,
                     help='entries per llama-embedding invocation (model load is paid once per invocation)')
    ap.add_argument('--threads', default=8, type=int)
    args = ap.parse_args()

    entries = json.loads(args.celia_index.read_text())
    print(f'{len(entries)} entries from {args.celia_index}', file=sys.stderr)

    all_vecs: list = []
    dim = 0
    started = time.time()
    for start in range(0, len(entries), args.chunk_size):
        chunk = entries[start:start + args.chunk_size]
        texts = [embedding_text(e) for e in chunk]
        vecs = embed_chunk(args.llama_embedding, args.model, texts, args.threads)
        if dim == 0:
            dim = len(vecs[0])
        all_vecs.extend(vecs)
        elapsed = time.time() - started
        print(f'{start + len(chunk)}/{len(entries)} ({elapsed:.1f}s elapsed)', file=sys.stderr)

    if len(all_vecs) != len(entries):
        print(f'ERROR: got {len(all_vecs)} vectors for {len(entries)} entries', file=sys.stderr)
        return 1

    header = struct.pack('<6I', MAGIC, FORMAT_VERSION, len(entries), dim,
                          source_hash(entries), model_hash())
    payload = struct.pack(f'<{len(entries) * dim}f', *(x for vec in all_vecs for x in vec))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(header + payload)
    print(f'wrote {args.out} ({len(header) + len(payload)} bytes, dim={dim}) in {time.time() - started:.1f}s',
          file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
