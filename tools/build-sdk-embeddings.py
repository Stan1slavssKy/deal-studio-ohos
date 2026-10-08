#!/usr/bin/env python3
"""
Precomputes EmbeddingGemma vectors for every entry in tools/sdk-index.json,
host-side, and writes them in the exact binary format
VeraSdkEmbeddingCache.ets (findSdkFunctionByEmbedding's corpus cache)
expects -- so a fresh install reads a bundled rawfile instead of spending
~31 minutes computing all 16,511 vectors on-device the first time, the real
measured cost of doing this one entry at a time through the native
llamaEmbedBatch binding.

This is the embeddings counterpart to tools/build-sdk-index.py: same "static
text, read once per SDK version" shape, but driven by the llama-embedding
CLI (entry/src/main/cpp/llama.cpp/build-host/bin/llama-embedding -- a host
build of the same llama.cpp vendored for the app, built with
`cmake -B build-host -DLLAMA_BUILD_EXAMPLES=ON` from entry/src/main/cpp/
llama.cpp) against the same GGUF the app downloads
(VeraEmbeddings.MODEL_FILE / EMBED_MODEL_URL).

The two hash functions below (fnv1a, source_hash, model_hash) are a
byte-for-byte port of VeraSdkEmbeddingCache.ets's own -- same seed, same
prime, same per-character update -- because the whole point of the two
hashes in the cache header is for the app to tell, on its own, whether this
bundled file still matches the corpus it was built from (source_hash, over
every entry's kit.module.name) and the model it was built with (model_hash,
over the GGUF filename). A real version drift here is exactly the failure
mode an app-side check that didn't verify both could miss silently -- it
already did, once, before model_hash existed.

Usage (--sdk-index defaults to the bundled rawfile, the one that matters):
    python3 tools/build-sdk-embeddings.py \
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

MAGIC = 0x56534431  # 'VSD1' -- must match VeraSdkEmbeddingCache.ets's MAGIC
FORMAT_VERSION = 4  # must match FORMAT_VERSION there; 4 = text is the summary, one entry per function
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
        key = f"{e['kit']}.{e['module']}.{e['name']}"
        h = fnv1a(key, h)
    return h


def model_hash() -> int:
    return fnv1a(MODEL_FILE, 0x811c9dc5)


def embedding_text(e: dict) -> str:
    # Must match VeraSdkEmbeddingCache.ets's sdkEmbeddingText exactly -- a
    # different text here embeds a different thing than the live on-device
    # path would for the same entry, silently.
    # kit module name, then the summary (what it does and what it is for, in
    # everyday words) in place of the description; an entry without one falls
    # back to its description. Must match sdkEmbeddingText exactly.
    parts = [e['kit'], e['module'], e['name'], e.get('summary') or e.get('description') or '']
    text = ' '.join(p for p in parts if p)
    # One entry, one line, when fed to llama-embedding's -f (newline-
    # separated prompts) -- strip any embedded newlines rather than let one
    # entry split into two prompts.
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
    # llama-embedding's stdout mixes LOG() progress lines with the final
    # array -- the array is the only line starting with '['.
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
    # The bundled rawfile, not tools/sdk-index.json -- that's the one
    # loadSdkIndex() actually reads at runtime (VeraSdkIndex.ets), and the
    # two can silently diverge (confirmed this session: they did, from
    # unrelated prior work on tools/build-sdk-index.py sitting uncommitted).
    # Embedding against the wrong copy means every sourceHash check at
    # runtime fails and the bundled cache is rejected as stale even though
    # nothing about the corpus actually changed.
    ap.add_argument('--sdk-index', default=Path('entry/src/main/resources/rawfile/sdk-index.json'), type=Path)
    ap.add_argument('--out', default=Path('entry/src/main/resources/rawfile/sdk-embeddings.bin'), type=Path)
    ap.add_argument('--chunk-size', default=2000, type=int,
                     help='entries per llama-embedding invocation (model load is paid once per invocation)')
    ap.add_argument('--threads', default=8, type=int)
    args = ap.parse_args()

    entries = json.loads(args.sdk_index.read_text())
    print(f'{len(entries)} entries from {args.sdk_index}', file=sys.stderr)

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
