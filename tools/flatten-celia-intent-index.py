#!/usr/bin/env python3
"""
Flattens tools/celia-intent-index.json ({bundle/IntentName: {summary, params,
...}}) into the rawfile the app reads: entry/src/main/resources/rawfile/
celia-intent-index.json, a flat array -- the same shape sdk-index.json
already has, so VeraCeliaIntentIndex.parseCeliaIntentIndex() mirrors
VeraSdkIndex.parseSdkIndex() entry for entry.

Audit-only fields (tool, fixed, paramSource, source) stay in the host file
and are dropped here, the same way build-intent-index.py already drops
intent-summaries.json's own source/reviewed before bundling.

Order: build-celia-intent-index.py -> this -> build-celia-intent-embeddings.py
(writes rawfile celia-intent-embeddings.bin from the same rows; rerun it
whenever a summary or a param changes).

Run after tools/build-celia-intent-index.py. Which intents a given device
actually has is decided on the phone at run time (VeraIntentRegistry); this
only supplies words and parameters for whatever celia names.
"""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = root / 'tools/celia-intent-index.json'
out = root / 'entry/src/main/resources/rawfile/celia-intent-index.json'
rows = json.loads(src.read_text())

flat = []
for key, row in sorted(rows.items()):
    bundle, intent_name = key.split('/', 1)
    flat.append({
        'bundle': bundle,
        'intentName': intent_name,
        'name': row['tool'],
        'description': row['summary'],
        'params': [{
            'name': p['name'],
            'platformName': p['platformName'],
            'kind': p['kind'],
            'values': p['values'],
            'required': p['required'],
            'description': p['description'],
        } for p in row['params']],
    })

out.write_text(json.dumps(flat, ensure_ascii=False, indent=0))
print(f'{len(flat)} celia intents -> {out.relative_to(root)}', file=sys.stderr)
