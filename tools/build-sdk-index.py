#!/usr/bin/env python3
"""
Builds a flat, searchable index of the OpenHarmony system API surface, so a
generated program can eventually reach it through one dispatcher the way it
reaches insight intents through `intent.call` -- except this surface has no
on-device registry and no curated catalogue to lean on: interface_sdk-js
declares on the order of 6,000+ functions across 529 top-level modules, and
probing each one by hand the way docs/intents-design.md section 7 does for
intents does not scale here.

What makes selecting from this surface possible at all without hand-testing
every function is a tag Huawei already writes into the source: every
@ohos.*.d.ts file carries a JSDoc `@kit <Name>` tag -- the platform's own
grouping (CalendarKit, TelephonyKit, AbilityKit, ArkUI, ...), about 47
distinct values, sharply skewed in size (most kits are one file with a
handful of functions; a few, ArkUI and AbilityKit chief among them, run to
hundreds of declarations each). This script reads that tag and every
function/method signature it can find, off a local interface_sdk-js checkout,
and writes one flat JSON array of
{kit, module, name, params, returnType, description, since, deprecated,
systemapi, permission, file}. No device, no network, no per-item review --
just static text, read once per SDK version.

It is deliberately a heuristic, not a TypeScript parser: regex plus a small
brace-depth scope tracker, matching the level of rigor tools/prompt-
coverage.py already uses elsewhere in this repo rather than a
`typescript`/AST dependency. Known failure modes, meant to be sanity-checked
by hand against the actual output rather than engineered away:

  - a nested generic type parameter list on a method (`foo<T extends Bar<K>>`)
    is matched only up to the first `>`, so an unusually complex bound can
    throw off that one declaration;
  - a deeply nested namespace can attribute a declaration to the wrong
    enclosing scope if formatting is unusual;
  - an interface member that reads exactly like a property signature with a
    parenthesised type is not distinguishable from a method by this script
    and may be missed or mismatched.

Usage:
    python3 tools/build-sdk-index.py --sdk-dir ~/work/ohos/interface/sdk-js/api
    python3 tools/build-sdk-index.py --sdk-dir <path> --out tools/sdk-index.json
"""

import argparse
import collections
import json
import re
import sys
from pathlib import Path

BLOCK_COMMENT_RE = re.compile(r'/\*.*?\*/', re.DOTALL)
LINE_COMMENT_RE = re.compile(r'//[^\n]*')
BRACE_RE = re.compile(r'[{}]')

KIT_RE = re.compile(r'@kit\s+(\S+)')
SINCE_RE = re.compile(r'@since\s+(\S+)')
PERMISSION_RE = re.compile(r'@permission\s+(.+)')
DEPRECATED_RE = re.compile(r'@deprecated\b')
SYSTEMAPI_RE = re.compile(r'@systemapi\b')

# `declare namespace X {` / `class X {` / `interface X {` / `enum X {` --
# opens a scope with a name. A bare `{` with none of these just deepens
# whatever scope is already open (an object type literal, a function type,
# a method body that can't exist in an ambient .d.ts but might in a comment
# example -- comments are stripped before this ever runs).
SCOPE_OPEN_RE = re.compile(
    r'\b(?:declare\s+)?(?:namespace|class|interface|enum)\s+(\w+)[^{;]*\{'
)

# A callable signature at statement scope: `function NAME(`, or a class/
# interface method `NAME(` (optionally `static`, optionally optional `?`,
# optionally generic `<T>`). The parameter list itself is found afterwards by
# counting parens, not by this regex, so a nested arrow-type parameter
# doesn't truncate the match.
DECL_START_RE = re.compile(
    r'(?:^|[\n;{])\s*(?:export\s+)?(?:static\s+)?(?:function\s+)?'
    r'(?P<name>\w+)\??\s*(?:<[^{};]*>)?\s*\('
)

RETURN_TYPE_RE = re.compile(r'\s*\??\s*:\s*([^;{]+);')

RESERVED = {
    'if', 'for', 'while', 'switch', 'catch', 'function', 'return', 'new',
    'typeof', 'declare', 'namespace', 'class', 'interface', 'enum', 'type',
    'constructor', 'get', 'set',
}


def strip_comments(text):
    """code (same length as text, block/line comments blanked to spaces,
    newlines kept) and the list of (start, end, raw) block comments, in the
    original text's coordinates -- so offsets found in `code` still index
    correctly into `comments`."""
    comments = []

    def blank(m):
        comments.append((m.start(), m.end(), m.group(0)))
        return ''.join(ch if ch == '\n' else ' ' for ch in m.group(0))

    code = BLOCK_COMMENT_RE.sub(blank, text)
    code = LINE_COMMENT_RE.sub(lambda m: ' ' * len(m.group(0)), code)
    return code, comments


def find_matching_paren(code, start):
    """`start` is the index right after an opening '(' (depth already 1).
    Returns the index of the matching ')', or None if it doesn't close within
    a generous window -- a parameter list that long is a parse failure
    either way."""
    depth = 1
    limit = min(len(code), start + 20000)
    i = start
    while i < limit:
        c = code[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def stmt_boundary(code, pos):
    """The closest '\\n', ';' or '{' before `pos` -- the real start of this
    statement. Not `m.start()`: a greedy `\\s*` in DECL_START_RE happily spans
    an entire blanked-out comment, so the regex match itself anchors to the
    leftmost boundary character it can reach rather than the nearest one,
    which is the wrong one to compare against a preceding JSDoc block."""
    return max(code.rfind('\n', 0, pos), code.rfind(';', 0, pos),
               code.rfind('{', 0, pos), 0)


def find_declarations(code):
    """One dict per callable-shaped signature in `code`, with its enclosing
    named scope (namespace/class/interface) resolved via a brace-depth stack
    walked alongside the declaration matches, both in position order."""
    named_open_at = {m.end() - 1: m.group(1) for m in SCOPE_OPEN_RE.finditer(code)}
    brace_events = [(m.start(), 1 if m.group() == '{' else -1)
                     for m in BRACE_RE.finditer(code)]

    stack = []
    bi = 0
    results = []
    for m in DECL_START_RE.finditer(code):
        pos = m.start('name')
        while bi < len(brace_events) and brace_events[bi][0] < pos:
            bpos, delta = brace_events[bi]
            if delta == 1:
                stack.append(named_open_at.get(bpos))
            elif stack:
                stack.pop()
            bi += 1

        name = m.group('name')
        if name in RESERVED:
            continue
        params_end = find_matching_paren(code, m.end())
        if params_end is None:
            continue
        rm = RETURN_TYPE_RE.match(code, params_end + 1)
        if not rm:
            continue
        module = next((s for s in reversed(stack) if s), None)
        results.append({
            'name': name,
            'params': ' '.join(code[m.end():params_end].split()),
            'returnType': rm.group(1).strip(),
            'module': module,
            'pos': pos,
            # The nearest preceding boundary, not the name position itself:
            # `function`/`static`/`export` sit between a JSDoc block and the
            # name, and counting that leading keyword as "something else in
            # between" would wrongly disown a real doc comment.
            'stmt_start': stmt_boundary(code, pos),
        })
    return results


def parse_jsdoc(raw):
    body = raw.strip()
    if body.startswith('/*'):
        body = body[2:]
    if body.endswith('*/'):
        body = body[:-2]
    description = ''
    for line in body.splitlines():
        line = line.strip().lstrip('*').strip()
        if not line or line.startswith('@'):
            continue
        description = line
        break
    since_m = SINCE_RE.search(raw)
    permission_m = PERMISSION_RE.search(raw)
    return {
        'description': description,
        'since': since_m.group(1) if since_m else '',
        'deprecated': bool(DEPRECATED_RE.search(raw)),
        'systemapi': bool(SYSTEMAPI_RE.search(raw)),
        'permission': permission_m.group(1).strip() if permission_m else '',
    }


EMPTY_JSDOC = {'description': '', 'since': '', 'deprecated': False,
               'systemapi': False, 'permission': ''}


def attach_jsdoc(decls, code, comments):
    """A declaration gets the nearest preceding block comment only if
    nothing but whitespace sits between them -- otherwise it was documenting
    something else."""
    ci = 0
    last = None
    for d in decls:
        while ci < len(comments) and comments[ci][0] < d['stmt_start']:
            last = comments[ci]
            ci += 1
        info = EMPTY_JSDOC
        if last is not None:
            _, cend, raw = last
            if cend <= d['stmt_start'] and code[cend:d['stmt_start']].strip() == '':
                info = parse_jsdoc(raw)
        d.update(info)
    return decls


def module_fallback(path):
    stem = path.name
    if stem.endswith('.d.ts'):
        stem = stem[:-len('.d.ts')]
    if stem.startswith('@ohos.'):
        stem = stem[len('@ohos.'):]
    return stem


def process_file(path, sdk_root):
    text = path.read_text(encoding='utf-8', errors='replace')
    code, comments = strip_comments(text)

    kit = None
    for (_, _, raw) in comments:
        m = KIT_RE.search(raw)
        if m:
            kit = m.group(1)
            break
    if kit is None:
        return None

    decls = find_declarations(code)
    attach_jsdoc(decls, code, comments)
    rel = str(path.relative_to(sdk_root))
    fallback = module_fallback(path)

    return [{
        'kit': kit,
        'module': d['module'] or fallback,
        'name': d['name'],
        'params': d['params'],
        'returnType': d['returnType'],
        'description': d['description'],
        'since': d['since'],
        'deprecated': d['deprecated'],
        'systemapi': d['systemapi'],
        'permission': d['permission'],
        'file': rel,
    } for d in decls]


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--sdk-dir', required=True,
                     help='path to the interface_sdk-js api/ directory')
    ap.add_argument('--out', default='tools/sdk-index.json',
                     help='where to write the JSON index (default: tools/sdk-index.json)')
    args = ap.parse_args()

    sdk_root = Path(args.sdk_dir).expanduser().resolve()
    if not sdk_root.is_dir():
        print(f'error: {sdk_root} is not a directory', file=sys.stderr)
        return 1

    files = sorted(sdk_root.glob('*.d.ts'))
    if not files:
        print(f'error: no .d.ts files directly under {sdk_root}', file=sys.stderr)
        return 1

    all_entries = []
    skipped_no_kit = []
    per_kit = collections.Counter()

    for path in files:
        entries = process_file(path, sdk_root)
        if entries is None:
            skipped_no_kit.append(path.name)
            continue
        all_entries.extend(entries)
        for e in entries:
            per_kit[e['kit']] += 1

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    # ensure_ascii=True (the default): the on-device loader
    # (loadRawfileText, LlamaEngine.ets) decodes rawfile bytes one-to-one into
    # char codes, not as UTF-8, so a raw non-ASCII byte would come out
    # mangled. \uXXXX escapes sidestep that instead of writing a second
    # decoder just for this file -- interface_sdk-js is overwhelmingly ASCII
    # already (26 stray bytes out of 6.5MB on this checkout).
    out_path.write_text(json.dumps(all_entries, indent=1), encoding='utf-8')

    print(f'{len(files)} files scanned, {len(skipped_no_kit)} skipped (no @kit tag)')
    print(f'{len(all_entries)} candidate entries across {len(per_kit)} kits')
    print(f'wrote {out_path}')
    print()
    print('entries per kit, largest first:')
    for kit, count in per_kit.most_common():
        print(f'  {count:5d}  {kit}')
    if skipped_no_kit:
        print()
        print(f'{len(skipped_no_kit)} files had no @kit tag (skipped):')
        for name in skipped_no_kit[:20]:
            print(f'  {name}')
        if len(skipped_no_kit) > 20:
            print(f'  ... and {len(skipped_no_kit) - 20} more')
    return 0


if __name__ == '__main__':
    sys.exit(main())
