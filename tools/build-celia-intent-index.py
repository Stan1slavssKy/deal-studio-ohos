#!/usr/bin/env python3
"""
Writes the search-index entry for every intent celia's own tool catalogue
names a concrete bundle for: a plain-language summary (DeepSeek, same prompt
and batching as build-intent-summaries.py) plus the real, resolved call
parameters -- not left to the summary's prose to mention or not.

Input, which does not live in this repository:
  --celia    a directory holding insight_intent_tools.json and
             insight_intent_execute_map.json, unpacked from the assistant's
             own HAP (/system/app/HwHmosVAssistant/HwHmosSystemAgent.hap,
             resources/rawfile/).

Unlike build-intent-summaries.py, there is no --db here and no pulled device
snapshot of any kind: celia names far more intents (844 tools, 610 of them
with a real declared parameter schema) than any one device installs, and
which of them a given device actually has is a question for runtime
(VeraIntentRegistry), never for what gets indexed. A row here can describe an
intent no device in this building has ever had installed; that is fine --
nothing unindexed can be *offered* on a device that lacks it either way, the
same closed loop intent.call already keeps.

Celia's own parameter names are its internal field names, not necessarily the
literal wire key insightIntentDriver.execute() expects -- the real mapping is
in execute_map.json's own intentParam template ("platformKey":
"${celiaField}"). tools/intent_import.resolve_template_params resolves this
the same way the hand-curated catalogue's own import pipeline already does;
this script reuses that function rather than reading celia's names as if they
were wire keys.

The celia text is proprietary and is only a lead, same as build-intent-
summaries.py: the model is told to write fresh English, never to translate or
quote it. A tool celia declares no description for still gets a row, summary
written from its name and resolved parameters alone.

Output: tools/celia-intent-index.json, { "bundle/IntentName": {"summary":
"...", "source": "celia", "tool": "...", "params": [...], "fixed": {...},
"paramSource": "resolved"|"schema-only"} }. Rerunning skips the DeepSeek call
for what already has a summary, but always refreshes the resolved-parameter
fields from the current celia files, since those can improve without needing
a new summary.

Usage:
    python3 tools/build-celia-intent-index.py --celia ~/work/celia/rawfile \\
        --out tools/celia-intent-index.json
"""

import argparse
import importlib.util
import json
import sys
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


imp = load('intent_import', 'intent-import.py')            # load_celia, resolve_template_params
gen = load('build_intent_summaries', 'build-intent-summaries.py')  # flat_params, ask, sums, SYSTEM


def schema_only_params(properties: dict, required: list) -> list:
    """Fallback when the execute_map template is not a flat dict (a one-
    string template, or no template at all): no per-field wire key to
    resolve, so the schema's own names travel as-is -- weaker than a
    resolved row, but celia-primary means every tool still gets one."""
    return [{
        'name': field.strip().rstrip(':'), 'platformName': field.strip().rstrip(':'),
        'kind': 'int' if schema.get('type') == 'integer' else 'string',
        'values': [v for v in schema.get('enum', []) if isinstance(v, str)],
        'required': field.strip().rstrip(':') in required, 'defaultValue': '',
        'description': schema.get('description', ''),
    } for field, schema in properties.items()]


def collect(celia_dir):
    """
    key -> (deepseek_brief, resolved_row) for every celia tool naming one
    concrete, non-dynamic bundle/intent. Two dicts, not one: the brief is
    what gets sent to the model (facts to summarize from); the resolved row
    is this script's own structured output, merged in after the summary
    comes back, never shown to the model as a field name to copy.
    """
    tools, execute_map = imp.load_celia(celia_dir)
    briefs, resolved, dropped = {}, {}, defaultdict(int)
    for tool_name, entry in sorted(execute_map.items()):
        tool = tools.get(tool_name)
        bundle = entry.get('bundleName', '')
        intent = entry.get('insightIntentName', '')
        if tool is None:
            dropped['no matching tool'] += 1
            continue
        if bundle.startswith('${'):
            # The assistant lets its model choose the app. A search-index row
            # names one target; this can't, so it can't be one.
            dropped['dynamic bundle'] += 1
            continue
        if not bundle or not intent:
            dropped['no bundle/intent name'] += 1
            continue
        schema = tool.get('parameters') or {}
        properties = schema.get('properties') or {}
        # A stray trailing colon on a handful of celia's own schema keys
        # (data typo) must not make a param look optional just because
        # required's own spelling of its name doesn't match.
        required = [r.strip().rstrip(':') for r in (schema.get('required') or [])]
        template = entry.get('intentParam')
        if isinstance(template, dict):
            fixed, params = imp.resolve_template_params(template, properties, required)
            param_source = 'resolved'
        else:
            fixed, params = {}, schema_only_params(properties, required)
            param_source = 'schema-only'
        key = f'{bundle}/{intent}'
        if key in resolved and len(resolved[key]['params']) >= len(params):
            dropped['duplicate intent, kept richer tool'] += 1
            continue
        briefs[key] = {
            'intent': intent, 'bundle': bundle,
            'facts': [{'description': tool.get('description', ''),
                       'parameters': gen.flat_params(tool.get('parameters')),
                       'always_sends': fixed}],
            'source': 'celia',
        }
        resolved[key] = {'tool': tool_name, 'params': params, 'fixed': fixed,
                          'paramSource': param_source}
    return briefs, resolved, dropped


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--celia', required=True, type=Path)
    ap.add_argument('--out', required=True, type=Path)
    ap.add_argument('--key-file', default='~/.deepseek-key')
    ap.add_argument('--batch', type=int, default=8)
    ap.add_argument('--workers', type=int, default=8)
    ap.add_argument('--dry-run', type=int, default=0, metavar='N', help='print N rows and stop; no key read, no request')
    args = ap.parse_args()

    briefs, resolved, dropped = collect(args.celia.expanduser())
    n_resolved = sum(1 for r in resolved.values() if r['paramSource'] == 'resolved' and r['params'])
    print(f'{len(briefs)} celia intents, {n_resolved} with resolved wire parameters', file=sys.stderr)
    for reason, count in sorted(dropped.items(), key=lambda kv: -kv[1]):
        print(f'  dropped {count:4d}  {reason}', file=sys.stderr)

    if args.dry_run:
        for k in list(briefs)[:args.dry_run]:
            print(k)
            print(json.dumps(briefs[k], indent=1, ensure_ascii=False))
            print(json.dumps(resolved[k], indent=1, ensure_ascii=False))
            print()
        return 0

    done = json.loads(args.out.read_text()) if args.out.exists() else {}
    todo = {k: b for k, b in briefs.items() if k not in done}
    print(f'{len(done)} already done, {len(todo)} to do', file=sys.stderr)
    if todo:
        key = gen.sums.read_key(args.key_file)
        meter = gen.sums.Meter()
        items = sorted(todo.items())
        batches = [items[i:i + args.batch] for i in range(0, len(items), args.batch)]
        started = time.time()
        with ThreadPoolExecutor(args.workers) as pool:
            futures = [pool.submit(gen.ask, key, b, meter) for b in batches]
            for n, f in enumerate(as_completed(futures), 1):
                done.update(f.result())
                args.out.parent.mkdir(parents=True, exist_ok=True)
                args.out.write_text(json.dumps(done, indent=0, ensure_ascii=False, sort_keys=True))
                print(f'{n}/{len(futures)} batches, {len(done)} summaries, ~${meter.cost():.4f}, '
                      f'{time.time() - started:.0f}s', file=sys.stderr)
        print(f'calls={meter.calls} failed_batches={meter.failed} est_cost=${meter.cost():.4f} '
              f'missing={sum(1 for k, _ in items if k not in done)}', file=sys.stderr)

    # Always refresh the resolved-parameter fields from celia's current data,
    # even for a key already summarized: a template can resolve cleanly
    # after a celia update without needing a new summary written.
    for key, row in resolved.items():
        if key in done:
            done[key] = {**done[key], **row}
    # A key celia no longer names at all (a tool removed upstream) stops
    # being offered -- drop it rather than ship a stale, unreachable row.
    done = {k: v for k, v in done.items() if k in briefs}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(done, indent=0, ensure_ascii=False, sort_keys=True))
    print(f'{len(done)} rows -> {args.out}', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
