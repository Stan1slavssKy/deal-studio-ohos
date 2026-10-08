#!/usr/bin/env python3
"""
Says which of the phone's intents a prompt will actually be shown.

A prompt does not see the registry. It sees what describeTargetsForPrompt
(entry/src/main/ets/vera/VeraIntentRegistry.ets) lets through, and that is much
narrower than the 640 reachable intents:

  - Jev contributes at most four addresses -- one Choice per batch of 160, and a
    choice returns one option. Not modelled here: it needs a paid call and a
    model's judgement. What this prints is the lexical tail alone, the
    pessimistic case, which is the useful one -- a prompt that works without Jev
    works with it.
  - Everything else is ranked by how many words of the request, four characters
    or longer, occur as a SUBSTRING of intentName + ' ' + bundle, lowercased,
    plus one if the intent declares parameters. Ties break on the target string
    ascending, which is why com.ohos.sceneboard loses every one of them.
  - The whole list is cut off at 2000 characters, about twenty addresses.

So the wording of a prompt decides what the model can reach, and a prompt has
to be checked rather than guessed at. Three things this catches:

  a cluster crowded out of the budget -- a torch prompt that also mentions
  single-hand mode and screen orientation fills all twenty slots with
  com.huawei.* rows and OpenFlashlight never appears at all;

  a word fragment that matches something unintended -- "what came back" pulls in
  com.huawei.hmos.camera, because "came" is a substring of "camera";

  an expensive word -- --word says what one costs. "setting" occurs in 270 of the
  640 names and "switch" in 90, so either of them takes the whole prompt, while
  anything under four characters is free because the selector skips it.

Input, neither of which is committed:

  $INTENT_DB   insight_intent.db pulled off the device, the registry the OS
               itself keeps. Default ~/Desktop/hdc/insight_intent.db.

The prompts are read out of docs/prompts/intent-coverage.md, from the fenced
blocks, and the addresses each one claims out of the first column of its results
table -- so the claim and the worklist a person fills in are the same text.

Usage:
    python3 tools/prompt-coverage.py                 # every prompt, plus totals
    python3 tools/prompt-coverage.py --only 12       # one section, -v for detail
    python3 tools/prompt-coverage.py --missing       # what no prompt reaches
    python3 tools/prompt-coverage.py --word page     # what a word costs
    echo "some draft prompt" | python3 tools/prompt-coverage.py --stdin
"""

import argparse
import collections
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

BUDGET = 2000          # describeTargetsForPrompt's budgetChars default
MIN_WORD = 4           # it skips words shorter than this
REPO = Path(__file__).resolve().parent.parent
PROMPTS = REPO / 'docs' / 'prompts' / 'intent-coverage.md'


# ------------------------------------------------------------------ registry

class Entry:
    """One installed intent, flattened the way VeraIntentRegistry flattens it."""

    def __init__(self, bundle, module, ability, name, modes, params):
        self.bundle = bundle
        self.name = name
        self.modes = ' '.join(sorted(modes))
        self.params = params
        self.target = '/'.join([bundle, module, ability, name])
        self.short = bundle.split('.')[-1] + '/' + name

    def line(self):
        """renderEntry: the line this entry costs in the prompt."""
        out = '  ' + self.target + '  [' + self.modes + ']'
        if self.params:
            out += '  parameters: ' + ' '.join(self.params)
        return out + '\n'


def load_registry(db_path):
    """
    Every intent the app could call, from the pulled database.

    Dropped here for the same reason flatten() drops them on the device: an
    intent that runs in a service or UI extension cannot be reached by
    insightIntentDriver.execute as this app calls it. That is 640 of 810 rows.

    Metadata comes in the three shapes docs/intents-design.md section 2
    describes, and all three have to be normalised to one list of parameter
    names: the JSON-schema style under 'properties', the list style with
    'name', and the decorator's own 'parameters' object.
    """
    rows = sqlite3.connect(db_path).execute(
        'select INTENT_KEY, INTENT_VALUE from insight_intent_table').fetchall()
    entries, total = [], 0
    for key, value in rows:
        try:
            blob = json.loads(value)
        except ValueError:
            continue
        fallback = key.split('/')[1] if '/' in key else key
        for intent in blob.get('insightIntents') or []:
            total += 1
            params = []
            for spec in intent.get('inputParams') or []:
                if not isinstance(spec, dict):
                    continue
                if 'properties' in spec:
                    params += list(spec['properties'].keys())
                elif 'name' in spec:
                    params.append(spec['name'])
            entries.append(_flatten(intent, fallback, params))
        for intent in blob.get('extractInsightIntents') or []:
            total += 1
            schema = (intent.get('parameters') or {}).get('properties') or {}
            entries.append(_flatten(intent, fallback, list(schema.keys())))
    return [e for e in entries if e is not None], total


def _flatten(intent, fallback, params):
    ui = intent.get('uiAbility') or {}
    ability = ui.get('ability') or ''
    if not ability:
        return None
    return Entry(intent.get('bundleName') or fallback,
                 intent.get('moduleName') or '',
                 ability,
                 intent.get('intentName') or '',
                 ui.get('executeMode') or [],
                 params)


# ------------------------------------------------------------ the selection

def request_words(request):
    """
    requestWords: anything that is not a letter or a digit separates words.

    Splitting on spaces alone drops the last word of every clause, because the
    comma travels with it -- "my contacts," is a substring of nothing, and all
    eight of the Contacts app's intents score zero. The selector used to do
    exactly that; it does not any more, and this follows it.
    """
    return [w for w in re.sub(r'[^a-z0-9]+', ' ', request.lower()).split(' ') if w]


def visible(request, entries, budget=BUDGET):
    """
    The addresses this request would be shown, in order.

    A transcription of describeTargetsForPrompt's lexical tail, kept
    deliberately literal -- the same requestWords split, the same >=4 character
    substring test, the same +1 for a declared parameter list, the same
    score-then-target sort, the same running character budget. If that function
    changes, this has to change with it or the numbers below mean nothing.
    """
    words = request_words(request)
    scored = []
    for entry in entries:
        haystack = (entry.name + ' ' + entry.bundle).lower()
        score = sum(1 for w in words if len(w) >= MIN_WORD and w in haystack)
        if score == 0:
            continue
        if entry.params:
            score += 1
        scored.append((score, entry))
    scored.sort(key=lambda pair: (-pair[0], pair[1].target))

    shown, used = [], 0
    for _score, entry in scored:
        cost = len(entry.line())
        if used + cost > budget:
            break
        shown.append(entry)
        used += cost
    return shown, used, [e for _s, e in scored]


def why(request, entry):
    """Which words of the request matched, so a phantom match is visible."""
    haystack = (entry.name + ' ' + entry.bundle).lower()
    seen = []
    for word in request_words(request):
        if len(word) >= MIN_WORD and word in haystack and word not in seen:
            seen.append(word)
    return seen


def phantoms(request, entry):
    """
    Matches that are a fragment rather than a word.

    A word counts as real when it is a whole part of the intent name or the
    bundle -- a CamelCase part or a dotted component -- or, at six characters or
    more, the head or tail of one, which is how "launcher" legitimately matches
    litegamelauncher. Below that the coincidences take over: "came" matching
    camera and "line" matching BestSelectionPipeline are both four letters, and
    between them they cost four slots of a twenty-slot budget.
    """
    parts = set(re.findall(r'[a-z]+', re.sub(r'(?<!^)(?=[A-Z])', ' ',
                                             entry.name + ' ' + entry.bundle).lower()))
    out = []
    for word in why(request, entry):
        if word in parts:
            continue
        if len(word) >= 6 and any(p.startswith(word) or p.endswith(word) for p in parts):
            continue
        out.append(word)
    return out


# ------------------------------------------------------------- the md file

class Prompt:
    def __init__(self, number, title, text, reaches):
        self.number = number
        self.title = title
        self.text = text
        self.reaches = reaches


def read_prompts(path):
    """
    The prompts as the file states them, with the addresses each one claims.

    The claim is the first column of the prompt's results table: every
    `app/IntentName` in a row of it. The table is the worklist a person fills in
    as they run the prompt, so the claim and the worklist are the same text and
    cannot disagree.

    Without the claim this tool could only say what a prompt pulls in, never
    whether that is what the prompt was written for -- which is the whole
    question when the budget holds twenty of 640 addresses.
    """
    if not path.exists():
        sys.exit('no prompt file at ' + str(path))
    body = path.read_text(encoding='utf-8')
    out = []
    for chunk in re.split(r'^## ', body, flags=re.M)[1:]:
        head = chunk.split('\n', 1)[0].strip()
        match = re.match(r'(\d+)\.\s*(.+)', head)
        if not match:
            continue
        blocks = re.findall(r'^```\n(.*?)^```', chunk, flags=re.M | re.S)
        if not blocks:
            continue
        text = ' '.join(blocks[0].split())
        reaches = []
        for line in chunk.split('\n'):
            if not line.startswith('|'):
                continue
            found = re.findall(r'`([^`]+/[^`]+)`', line.split('|')[1])
            for short in found:
                if short not in reaches:
                    reaches.append(short)
        out.append(Prompt(int(match.group(1)), match.group(2), text, reaches))
    return out


def resolve(short, entries):
    """A short app/IntentName back to the entry it names, or None."""
    hits = [e for e in entries if e.short == short]
    return hits[0] if len(hits) == 1 else None


# ------------------------------------------------------------------ report

def report(prompt, entries, verbose):
    shown, used, all_scored = visible(prompt.text, entries)
    shown_targets = {e.target for e in shown}
    print('## %d. %s' % (prompt.number, prompt.title))
    print('   %d addresses, %d of %d chars' % (len(shown), used, BUDGET))

    missed, unknown = [], []
    for short in prompt.reaches:
        entry = resolve(short, entries)
        if entry is None:
            unknown.append(short)
        elif entry.target not in shown_targets:
            rank = next((i for i, e in enumerate(all_scored)
                         if e.target == entry.target), None)
            missed.append((short, rank))

    if unknown:
        print('   NOT ON THIS PHONE: ' + ', '.join(unknown))
    if missed:
        print('   CROWDED OUT (%d):' % len(missed))
        for short, rank in missed:
            where = 'ranked %d' % (rank + 1) if rank is not None else 'no word matched'
            print('     %-52s %s' % (short, where))

    noise = []
    for entry in shown:
        bad = phantoms(prompt.text, entry)
        if bad:
            noise.append((entry.short, bad))
    if noise:
        print('   PHANTOM MATCHES (a fragment, not a word):')
        for short, bad in noise:
            print('     %-52s from %s' % (short, ', '.join(bad)))

    if verbose:
        claimed = set(prompt.reaches)
        for entry in shown:
            mark = '*' if entry.short in claimed else ' '
            print('     %s %-52s %s' % (mark, entry.short, ' '.join(why(prompt.text, entry))))
    print()
    return shown_targets


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--db', default=os.environ.get(
        'INTENT_DB', str(Path.home() / 'Desktop' / 'hdc' / 'insight_intent.db')),
        help='insight_intent.db pulled off the device ($INTENT_DB)')
    parser.add_argument('--file', default=str(PROMPTS), help='the prompt file to read')
    parser.add_argument('--only', type=int, action='append', help='just this section number')
    parser.add_argument('--stdin', action='store_true', help='check one prompt from stdin')
    parser.add_argument('--missing', action='store_true',
                        help='list the reachable intents no prompt reaches')
    parser.add_argument('--word', action='append', metavar='W',
                        help='what one word costs: how many addresses it matches, and which')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='print every address shown, with the words that matched')
    args = parser.parse_args()

    db = Path(args.db).expanduser()
    if not db.exists():
        sys.exit('no intent database at %s -- pull it off the phone and set $INTENT_DB.\n'
                 'It is gitignored on purpose: it describes one phone and one firmware.' % db)
    entries, total = load_registry(str(db))
    print('registry: %d reachable of %d installed, %d apps\n'
          % (len(entries), total, len({e.bundle for e in entries})))

    if args.word:
        # What a word costs. The budget holds about twenty addresses, so a word
        # that matches sixty -- "switch", "setting", "page" -- spends the whole
        # prompt on whatever sorts first, and a word that matches none is free.
        # An inflection is usually the mistake: "recording" matches nothing at
        # all, because the intent is called StartRecord.
        for word in args.word:
            hits = [e for e in entries if word.lower() in (e.name + ' ' + e.bundle).lower()]
            if len(word) < MIN_WORD:
                print('%-16s free -- under %d characters, the selector skips it'
                      % (word, MIN_WORD))
                continue
            print('%-16s %3d' % (word, len(hits)), end='')
            if hits and len(hits) <= 12:
                print('  ' + ', '.join(e.short for e in sorted(hits, key=lambda e: e.short)))
            elif hits:
                apps = collections.Counter(e.bundle.split('.')[-1] for e in hits).most_common()
                print('  ' + ', '.join('%s %d' % (a, n) for a, n in apps))
            else:
                print()
        return

    if args.stdin:
        text = ' '.join(sys.stdin.read().split())
        report(Prompt(0, 'from stdin', text, []), entries, True)
        return

    prompts = read_prompts(Path(args.file))
    covered = set()
    for prompt in prompts:
        if args.only and prompt.number not in args.only:
            continue
        covered |= report(prompt, entries, args.verbose)

    if args.only:
        return
    print('--- %d prompts reach %d of %d reachable intents (%.0f%%)'
          % (len(prompts), len(covered), len(entries), 100.0 * len(covered) / len(entries)))
    if args.missing:
        print('\nno prompt reaches these:')
        for entry in sorted((e for e in entries if e.target not in covered),
                            key=lambda e: e.short):
            print('   ' + entry.short)


if __name__ == '__main__':
    main()
