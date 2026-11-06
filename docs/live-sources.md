# Live sources: a program that fetches its own figures

A request for a figure of the real world (the weather, an index, a rate, a price) used to give a program with the figures of a
search made once, at generation, written into it: "Live IMOEX value" showed 2488.71 for good and said so in a banner, and its
widget returned the constant 2515.89. Now such a figure is a **live figure** of the plan, shown by the **`live_figure` section**:
it looks for a **live source** -- a public JSON API that needs no key -- and the program fetches it itself, on the screen and on
its home-screen card.

## The plan, Jev and the section (`vera/NeedsPlan.ets`, `vera/VeraCompose.ets`, `vera/LiveBlock.ets`)

A new screen goes through the agent like any other (`docs/agent.md`); nothing is decided before the route.

1. The plan of needs has a type `live`: `{"type": "live", "id", "label", "means", "measure", "unit", "query"}`, at most three. A
   figure worked out from one (what the person's coins are worth) is a `figure` whose formula reads its id.
2. Jev answers one yes or no for each (`live.N`, `askLive`, taken above `LIVE_ABOVE` 0.65): is it a figure of the real world
   the screen fetches as it is now? Every yes goes to one `live_figure` section (`readLive`); a no goes to the written section,
   and a figure whose formula reads it is refused (unbound), so the route writes the screen whole.
3. The section's call is written by the host, not a model (`FragmentSpec.hostFields`, `liveValues`): the source finder below,
   with the plan's figures in order (`liveNeed`); with no API, a search on each refresh (`Vera.Live.fetch`, the plan's
   `query` and labels); with no search either (no Exa key), the section cannot be filled and the screen is written whole.
4. The section is small and fixed (`liveFigureFragment` in `VeraTemplates.ets`): the first figure is an accent tile across the
   whole width with how it moved since the last answer ("▲ +0.20 (3.39%) since 14:30"; not for a weather code), the others are
   tiles in pairs below it (one alone takes the row); a placeholder box until the first answer; an info button that shows
   "<domain> · <time>" as a line under the first figure, in its tile, and hides it again; Refresh beside it, which says
   "Updating..." and is off while a request is out (one at a time; no silent ten-second wait), and after the answer a badge
   "Updated 15:22", with "· no change" when nothing moved -- a refresh that changed nothing looked like a tap that did nothing.
   An answer that does not come in 20 s says so. The change is told in as many places as the figure has ("-0.00010" for a
   rate, "<0.01%" for a tiny share); a ticker (every 60 s for an API, 300 s for a search); and a warning
   when a fetch fails, which keeps the figures shown. The tiles are a section of their own, so it draws no card around theirs.
   It starts empty and fetches a second after it opens: no figure on it was written by a model. Its handler reads the answer's
   lines in their places by construction, so the checks that once sent a model-written program back (`sourceUseError`, and
   `sourceShownError` on the phone) are not needed; `sourceShownError` stays as a host check, and finds the source missing
   until the info button is tapped, as it should. A WMO weather code (Open-Meteo's `weather_code`) is shown in words, and an
   ISO time as its hours and minutes.
   The renderer's `TileGrid` drew a tile alone in its row, and then every tile, as tall as the whole scroll
   (`height('100%')` and `ItemAlign.Stretch` with no height to be a share of): tiles are now as tall as what they hold, and a
   tile of a pair at least as tall as a label and a full-size figure (`tilePairHeight`), so a word that shrinks to fit
   ("Overcast") does not leave it shorter than its neighbour.
5. Ports: `live1`, `live2`, `live3` (numbers, read off the text with its currency sign and separators: `$1,234.56` is 1234.56),
   `live_source`, `live_asof`. The plan's formulas read the figures as operands (listed first, so a price times a count is
   offered), the written section is told of them (`partsContract`), and a catalogue section reads them by name.
6. One per screen, so its names are its own (`indexed` false). A structural edit does not add one (no source is looked for
   then); it can remove or move it.

## Finding a source (`vera/VeraSourceFind.ets`, at generation)

Run by the section's fill (`fillLive`, `SectionFill.ets`), before the content of the other sections:

1. One web search: the figure plus "free public JSON API no API key".
2. DeepSeek (`SOURCE_FIND_PROMPT`, no thinking) proposes up to three GET addresses with every parameter filled in.
3. Each is fetched (`httpGetText`: https only, no credentials in it, no host on this network, size limit, short timeouts). A
   JSON answer is shown to DeepSeek as a sample (`sampleOf`: lists of records cut to three, a list of plain values -- column
   names, a row -- kept to sixty), and it names where each figure is: a path such as `marketdata.data[0][4]`, a label, a unit,
   and the path of the time the data is for (`SOURCE_PICK_PROMPT`).
4. The address is fetched again and the host reads the paths itself. A source is taken only when every path holds a value.
   The model never gives a figure; it only says where one is.

## No API found: the program reads a search (`Vera.Live.fetch`)

When the finder finds nothing, the section calls `sdk.call("Vera.Live.fetch", ["query", <the plan's query>, "labels", "A|B|C"],
"liveAnswer")` (`searchSpec`, `sourceArgs`): on each refresh the phone searches, DeepSeek reads up to three figures off the
results, and only a figure whose text is in the result it names is given (`VeraLive.ets`). The answer has the same lines. The
query and labels are written out (E2114). A search refresh costs a search and a model call and takes 3-10 s, so the section
refreshes every five minutes at most, and its widget does not refresh on the card: Make widget is told not to call it there,
and the card shows what the app fetched last.

Host runs of the earlier path (the model wrote the program on `sourceNote`; `source-run.js` now runs the section instead): Tesla stock price -- no keyless API (403, end-of-day only), read off a
search: `$401.68` from exa.ai's market page, the program on its first attempt once the check carried a figure with a currency
sign (before that, `strings.toNumber("$401.83")` gave the fallback and the screen kept the first figure); the current Real
Madrid score -- no API (403s), first figures from the search at generation (0-3, FT), the refresh's search did not contain them
and the screen said "Source unavailable" and kept them.

## The call (`vera/VeraSource.ets`, on the phone)

```
sdk.call("Vera.Source.fetch", ["url", "https://...", "paths", "a.b|c[0][1]", "asof", "d"], "onSource")
```

One GET, read at the paths. The answer has the lines of `Vera.Live.fetch`: `ok`, up to three figures (an empty line for one not
asked), `source<TAB>domain<TAB>address`, `asof<TAB>time`; or one line `error: ...`. The compiler takes the parameters only as
written-out strings (E2114), so nothing the program keeps can go out in an address. E2114 applies to `Vera.Live.fetch`'s query
and labels too: a saved program that built its query from its state stops compiling on its next change.

The address comes from a model reading web pages, which a page can steer, so it is held to a public host twice:
`sourceUrlError` (at generation and before each request) refuses a host written as a number in any form (decimal, octal or hex
IPv4, IPv6), `localhost` and local names (`.local`, `.lan`, `.internal`, `.home.arpa`, ...), a trailing dot ignored; on the
phone `publicHostError` resolves the name and refuses it when any address is loopback, private, link-local, CGNAT or
unique-local. Redirects are not followed (`maxRedirects: 0`): a 3xx is an error. A name that resolves differently between the
check and the request (DNS rebinding) is not covered.

## On the card

`widgetRefresh` may make this one call (and no other phone effect), and so may a widget's button (a Refresh): the card
(`LiveFormService`) makes it, hands the answer to the handler, then draws and saves. One call per refresh or tap, with 3 s to
connect and 4 s to read: the card's update has about ten seconds. The answer is handed to the state saved by the time it
arrives: when the app saved during the fetch, its state is kept and the answer applied to it. The once-per-period mark is set
before the fetch, so cards of one project updated together fetch once. Make widget tells the model so; its check
answers the call with a failure, which the handler must take and still draw. The card's update runs `widgetRefresh` when the card
is added and then about every 30 minutes (once per project per 20 minutes, `RefreshLedger`).

## Measured

### The `live_figure` section, phone, 2026-11-06

| request | what happened | ready |
|---|---|---|
| Bitcoin price now | plan: one live figure; Jev `live.0` yes@1.00; no keyless API (tinymind.eu 502, openbitcoin.com and another not JSON), so a search on each refresh; no model wrote code; $76,173.84 from exa.ai a second after it opened | 8.1 s (the earlier path: 36 s, the model writing the whole program, its first attempt not compiling) |
| Value of my bitcoin holdings | plan: Bitcoin held (input), the price (live), Holdings value = held × price; one section and the composer's parts; 1 × $76,173.84, then 2.5 typed: $190,434.60 | 15.6 s (7.2 s of it the plan) |
| Grocery list app | no live figure in the plan, no `live.N` asked; `checklist`, as before | 4.0 s |
| What is the weather today? | first run: a "Place" input that fed nothing (the call is a literal), a search with no place (the finder proposed Pensacola), "10° °C", and "High today" refused as a forecast, with a "Not available" notice. Fixed: the plan asks which place (a question with a default) and puts it in each figure's query, which the finder is given; today's forecast is live; a fourth figure is left out on the Metrics tab; the degree sign is not doubled. Second run, London: Open-Meteo, 3 of 3 paths, 10.3 °C, Overcast (the WMO code in words), high 11.1 °C, "From api.open-meteo.com · 11:30" (the source's own time, GMT here), refreshed every minute | 6.3 s after the answer |
| Euro to dollar rate (the tiles, 2026-11-06) | Jev `live.0` yes@1.00; api.exchangerate.dev, 1 of 1 path; the rate in the accent tile, the info button shows "api.exchangerate.dev · 11:52" under it | 9.6 s |

Not yet seen on the phone: Make widget on a screen with the section.

### The earlier path (the model wrote the program on `sourceNote`)


Host (`tools/vera-harness/source-run.js`: finder, program, then the program run with its own ticker and the real GET), deepseek-
flash, 2026-11-03, one run each, after the fixes below: Moscow weather (Open-Meteo), IMOEX (MOEX ISS), USD/RUB (frankfurter.dev),
Bitcoin (CoinMarketCap's public API), Beijing air quality (beijing.gov.cn), ISS position (wheretheiss.at): 6/6 found, written on the
first attempt, fetched by their own ticker a second after opening and shown with the source and the time; 10-15 s from request to
program, the GET itself 0.1-0.8 s. A source for a live Apple share price was not found (403, end-of-day only, 404).

Phone (Generate screen, then Make widget, Add widget):

| | result |
|---|---|
| Current weather in Moscow, auto-updated regularly | Open-Meteo; compiled on attempt 1; 0.9 °C fetched by the app in 248 ms; widget written; the card fetched it itself when added (241 ms) |
| Live IMOEX value | MOEX ISS; compiled on attempt 1; 2431.47 and its time fetched by the app; widget with a Refresh button written in 2.5 s; the card fetched when added (2432.74, 608 ms) and on its Refresh (2432.51, 1.35 s from tap to redraw) |

Found and fixed on the way:

- The sample cut every list to three items, so MOEX's column list stopped at `LASTVALUE` (the previous close) and the live
  `CURRENTVALUE` was never seen: the app showed yesterday's 2455.62 with "0.00 since previous reading".
- The first phone IMOEX app read the time from the line of the (empty) second figure: its value moved, its time never did.
  Hence `sourceShownError`.
- Make widget took three answers on the weather app: the model closed `import * as time from "std/time";` with a semicolon,
  which does not parse, and was told only "does not parse". The semicolon is now dropped and the parser's message passed on;
  host replay 6/6 on the first answer (~2 s).

Host checks: `source-check.js` (mocked search, model and network), `live-form-check.js` (the card's refresh and Refresh tap with
a mocked fetch), `widget-refine-check.js` (what a widget may call), example `tools/vera-harness/examples/widget-source.vera`.

## Limits

- Only what a free, keyless JSON API gives now is fetched on the card. Without one (live share prices outside MOEX, scores)
  the program reads a search on each refresh, which needs the Exa and DeepSeek keys on the phone, and its widget shows the
  figures the app fetched last. The finder can also take an end-of-day API for a "live" price (an Apple close from
  fin-node.net once; the same site was refused as not real-time on another run).
- The source is whatever the search turned up; an official one is preferred but not guaranteed (Bitcoin came from
  CoinMarketCap's public endpoint, air quality from the Beijing government's own page).
- At most three figures per source. A code (an Open-Meteo weather code) has to be turned into words by the program; when the
  three figures chosen did not include one, the weather widget described the wind instead.
- A free API can change or go away: the program then shows "error: ..." and keeps its last figures.
- The periodic update of a card already on the home screen follows the system's 30-minute schedule. Seen once on the phone: the
  weather card added at 14:44 was updated by the system at 15:16:49 and fetched Open-Meteo itself (374 ms), 0.9 °C to 0.6 °C.
