#!/usr/bin/env python3
"""
Writes a one-to-two sentence plain-language summary for every SDK function, so
search can match what a person wants ("make a beep") instead of what the
platform's own doc line says ("Writes the buffer.").

For each unique kit.module.name this reads the whole JSDoc of the function (every
overload, folded together) plus what its class says about itself, hands that to
DeepSeek, and stores one string per function. The result is a flat JSON object
{ "Kit.module.name": "summary", ... } -- a separate file from sdk-index.json, so
rebuilding the index never erases it, and rerunning this skips what is done.

It reuses tools/build-sdk-index.py's parser (same declarations, same scopes), so
the keys here are exactly the keys the index and the embedding cache use.

The key is read from a file (default ~/.deepseek-key), never from the command
line and never printed: this script's output and logs are safe to share.

Usage:
    python3 tools/build-sdk-summaries.py --sdk-dir ~/work/ohos/interface/sdk-js/api \\
        --out /tmp/sdk-summaries.json --pilot 150
    python3 tools/build-sdk-summaries.py --sdk-dir ... --out entry/src/main/resources/rawfile/sdk-summaries.json
"""

import argparse
import datetime
import importlib.util
import json
import random
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('build_sdk_index', HERE / 'build-sdk-index.py')
bsi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bsi)

BASE_URL = 'https://api.deepseek.com'
MODEL = 'deepseek-flash'  # SettingsStore.ets's DEFAULT_DEEPSEEK_MODEL

SYSTEM = """You write search-index summaries of OpenHarmony SDK functions. The index is searched with what a person wants to do, in everyday words, so a summary must be findable by that wish.

For each function write ONE or TWO plain sentences, at most 40 words:
 - first what it does, in plain words;
 - then what someone would use it for, in the everyday words for that task ("beep", "flashlight", "phone call", "where am I", "play a song"). Only name a use that follows directly from what the documentation says the function does -- never invent behaviour.
Do not mention kit or module names, API versions, promises, callbacks, error codes, or deprecation. Do not start with "This function".

Reply with one JSON object mapping each given key to its summary string, and nothing else."""

TAG_NOISE = ('@syscap', '@since', '@crossplatform', '@atomicservice', '@stagemodelonly',
             '@famodelonly', '@fa', '@form', '@test', '@kit', '@systemapi', '@permission',
             '@deprecated', '@useinstead', '@throws', '@returns', '@param', '@example')

RETURNS_RE = re.compile(r'^@returns?\s+(?:\{.*?\}\s*)?-?\s*(.*)$')
PARAM_FULL_RE = re.compile(r'^@param\s+(?:\{.*?\}\s*)?(\w+\s*-?\s*.*)$')
THROWS_RE = re.compile(r'^@throws\s+(?:\{.*?\}\s*)?-?\s*(.*)$')


def prose_of(raw):
    """Prose before the first @tag, whole (not just the first line), without the
    `> **NOTE**` blockquotes and link markup."""
    out = []
    for line in bsi.jsdoc_lines(raw):
        if line.startswith('@'):
            break
        if line.startswith('>') or not line:
            continue
        out.append(line)
    return bsi.clean_prose(' '.join(out))


def tag_lines(raw, regex):
    items = []
    current = None
    for line in bsi.jsdoc_lines(raw):
        m = regex.match(line)
        if m:
            current = [m.group(1)]
            items.append(current)
        elif line.startswith('@') or not line:
            current = None
        elif current is not None:
            current[0] += ' ' + line
    return [bsi.clean_prose(i[0]) for i in items if i[0].strip()]


def collect(sdk_root):
    """key -> {scope, sig, docs: [(prose, params, returns, throws)], flags}."""
    entries = {}
    for path in sorted(sdk_root.glob('*.d.ts')):
        text = path.read_text(encoding='utf-8', errors='replace')
        code, comments = bsi.strip_comments(text)
        kit = None
        for (_, _, raw) in comments:
            m = bsi.KIT_RE.search(raw)
            if m:
                kit = m.group(1)
                break
        if kit is None:
            continue
        decls = bsi.find_declarations(code)
        scope_doc = bsi.scope_docs(code, comments)
        fallback = bsi.module_fallback(path)
        ci = 0
        last = None
        for d in decls:
            while ci < len(comments) and comments[ci][0] < d['stmt_start']:
                last = comments[ci]
                ci += 1
            raw = ''
            if last is not None:
                _, cend, r = last
                if cend <= d['stmt_start'] and code[cend:d['stmt_start']].strip() == '':
                    raw = r
            module = d['module'] or fallback
            key = f"{kit}.{module}.{d['name']}"
            e = entries.setdefault(key, {
                'kit': kit, 'module': module, 'name': d['name'],
                'scope': scope_doc.get(d['module'], ''), 'sigs': [], 'docs': [],
                'deprecated': True, 'systemapi': True})
            e['sigs'].append(f"{d['name']}({d['params']}): {d['returnType']}")
            if raw:
                info = bsi.parse_jsdoc(raw)
                # An entry counts as deprecated/system only if every overload is.
                e['deprecated'] = e['deprecated'] and info['deprecated']
                e['systemapi'] = e['systemapi'] and info['systemapi']
                e['docs'].append({
                    'prose': prose_of(raw),
                    'params': [p for p in tag_lines(raw, PARAM_FULL_RE) if not p.startswith('callback')],
                    'returns': tag_lines(raw, RETURNS_RE),
                    'throws': tag_lines(raw, THROWS_RE),
                })
            else:
                e['deprecated'] = False
                e['systemapi'] = False
    return entries


def brief(e):
    """What goes to the model for one function: the longest prose among the
    overloads, the union of parameter notes, one return note, a few throws."""
    docs = e['docs']
    prose = max((d['prose'] for d in docs), key=len, default='')
    seen, params = set(), []
    for d in docs:
        for p in d['params']:
            if p not in seen:
                seen.add(p)
                params.append(p)
    returns = next((r for d in docs for r in d['returns']), '')
    throws = []
    for d in docs:
        for t in d['throws']:
            if t not in throws:
                throws.append(t)
    sig = min(e['sigs'], key=len)
    out = {'function': f"{e['module']}.{e['name']}", 'signature': sig}
    if e['scope']:
        out['class says'] = e['scope']
    if prose:
        out['doc'] = prose[:700]
    if params:
        out['parameters'] = '; '.join(params)[:500]
    if returns:
        out['returns'] = returns[:200]
    if throws:
        out['errors'] = '; '.join(throws)[:200]
    return out


def read_key(path):
    key = Path(path).expanduser().read_text().strip()
    if not key.startswith('sk-'):
        sys.exit(f'{path}: does not look like an API key')
    return key


def peak_now():
    n = datetime.datetime.now(datetime.timezone.utc)
    return n.weekday() < 5 and (1 <= n.hour < 4 or 6 <= n.hour < 10)


class Meter:
    def __init__(self):
        self.lock = threading.Lock()
        self.fresh = self.cached = self.output = self.calls = self.failed = 0

    def add(self, usage):
        with self.lock:
            hit = usage.get('prompt_cache_hit_tokens', 0)
            self.cached += hit
            self.fresh += usage.get('prompt_tokens', 0) - hit
            self.output += usage.get('completion_tokens', 0)
            self.calls += 1

    def cost(self):
        p = 2 if peak_now() else 1
        return (self.cached * 0.003 * p + self.fresh * 0.15 * p + self.output * 0.60 * p) / 1e6


def ask(key, batch, meter, timeout=120):
    """One request for a batch of functions -> {key: summary}. Retries on a
    transient failure; a batch that still fails is returned empty and reported."""
    items = {k: brief(e) for k, e in batch}
    body = json.dumps({
        'model': MODEL, 'temperature': 0.2, 'max_tokens': 4096, 'stream': False,
        'thinking': {'type': 'disabled'},
        'response_format': {'type': 'json_object'},
        'messages': [{'role': 'system', 'content': SYSTEM},
                     {'role': 'user', 'content': 'Functions (JSON):\n' + json.dumps(items, indent=0)}],
    }).encode()
    req = urllib.request.Request(BASE_URL + '/chat/completions', data=body, headers={
        'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key})
    last = ''
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = json.load(r)
            meter.add(data.get('usage', {}))
            got = json.loads(data['choices'][0]['message']['content'])
            return {k: v.strip() for k, v in got.items() if k in items and isinstance(v, str) and v.strip()}
        except urllib.error.HTTPError as e:
            last = f'HTTP {e.code}'
            if e.code in (400, 401, 402, 403):  # not transient
                break
        except Exception as e:  # network, timeout, bad JSON
            last = type(e).__name__
        time.sleep(2 * (attempt + 1))
    with meter.lock:
        meter.failed += 1
    print(f'  batch of {len(batch)} failed: {last}', file=sys.stderr)
    return {}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--sdk-dir', required=True, type=Path)
    ap.add_argument('--out', required=True, type=Path)
    ap.add_argument('--key-file', default='~/.deepseek-key')
    ap.add_argument('--pilot', type=int, default=0,
                    help='only this many functions: the gold targets first, then a seeded sample')
    ap.add_argument('--gold', default=HERE.parent / 'entry/src/main/resources/rawfile/sdk-selection-gold.json', type=Path)
    ap.add_argument('--batch', type=int, default=6)
    ap.add_argument('--workers', type=int, default=8)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--dry-run', type=int, default=0, metavar='N',
                    help='print the briefs of N selected functions and stop; no key read, no request')
    ap.add_argument('--include-system', action='store_true',
                    help='also summarise @systemapi-only functions (skipped by default)')
    args = ap.parse_args()

    entries = collect(args.sdk_dir.expanduser().resolve())
    print(f'{len(entries)} unique functions found', file=sys.stderr)
    todo = {k: e for k, e in entries.items() if args.include_system or not e['systemapi']}
    print(f'{len(todo)} after dropping system-only', file=sys.stderr)

    if args.pilot:
        gold = []
        for c in json.loads(args.gold.read_text()):
            gold += [t for t in c['gold'] if t in todo]
        rest = sorted(k for k in todo if k not in set(gold))
        random.Random(args.seed).shuffle(rest)
        keep = list(dict.fromkeys(gold))[:args.pilot]
        keep += rest[:max(0, args.pilot - len(keep))]
        todo = {k: todo[k] for k in keep}
        print(f'pilot: {len(todo)} functions ({len(set(gold))} gold targets)', file=sys.stderr)

    if args.dry_run:
        for k in sorted(todo)[:0] or list(todo)[:args.dry_run]:
            print(k); print(json.dumps(brief(todo[k]), indent=1)); print()
        return 0

    done = json.loads(args.out.read_text()) if args.out.exists() else {}
    todo = {k: e for k, e in todo.items() if k not in done}
    print(f'{len(done)} already done, {len(todo)} to do', file=sys.stderr)
    if not todo:
        return 0

    key = read_key(args.key_file)
    meter = Meter()
    items = sorted(todo.items())
    batches = [items[i:i + args.batch] for i in range(0, len(items), args.batch)]
    started = time.time()
    with ThreadPoolExecutor(args.workers) as pool:
        futures = [pool.submit(ask, key, b, meter) for b in batches]
        for n, f in enumerate(as_completed(futures), 1):
            done.update(f.result())
            if n % 10 == 0 or n == len(futures):
                args.out.parent.mkdir(parents=True, exist_ok=True)
                args.out.write_text(json.dumps(done, indent=0, ensure_ascii=True, sort_keys=True))
                print(f'{n}/{len(futures)} batches, {len(done)} summaries, '
                      f'~${meter.cost():.4f}, {time.time() - started:.0f}s', file=sys.stderr)
    print(f'calls={meter.calls} failed_batches={meter.failed} fresh_in={meter.fresh} '
          f'cached_in={meter.cached} out={meter.output} est_cost=${meter.cost():.4f} '
          f'({"peak" if peak_now() else "off-peak"} rates) missing={len(items) - sum(1 for k, _ in items if k in done)}',
          file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
