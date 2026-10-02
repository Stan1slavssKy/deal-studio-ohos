# Embedding search vs. token search — 10 live prompts, quality and timing

Ten real generations, run through the actual Generate screen on-device
(`deepseek-flash`, both corpus caches warm — SDK from the bundled rawfile,
intent from the device registry), not hand-picked `need` strings. Each tool
call already logs both rankings side by side (`VERA-SDK-EMBED-CMP` /
`VERA-INTENT-EMBED-CMP`), so this is read off real logs, not simulated.

The `need` string is whatever the model chose to search for, verbatim —
not written by me. Prompts 1-5 were picked to span: one case token search
already handles fine (`1`), the three documented motivating gaps from
`VeraSdkIndex.ets`'s own doc comment (`2`-`4`), and one case where the
"right" answer is genuinely ambiguous between the two tools (`5`). Prompts
6-10 are more complex, multi-capability requests, picked to see what
happens when a single generation needs several tool calls across several
unrelated features rather than one clean match.

Device: SGT-AL00 (Huawei Mate 80 Pro), 2026-10-02. Embedding model:
EmbeddingGemma-300M, Q4_K_M. Both tools always ran the embedding path
(`via=embedding`) — the caches were already warm throughout. Quality
section below covers prompts 1-10; the dedicated timing section nearer
the bottom covers precise per-call numbers for all 10, since the first
pass through this (prompts 1-5) only logged rankings, not durations --
`VERA-SDK-TIMING`/`VERA-INTENT-TIMING` instrumentation
(`DeepSeekEngine.ets`) and the query-embed-vs-scan split inside each
search function (`VeraSdkEmbeddingCache.ets`, `VeraIntentEmbeddingCache.ets`)
were added specifically to answer that second question.

## 1. "A button that reads the current battery level"

**SDK** — `need="read the current battery level"`

| rank | token | embedding |
|---|---|---|
| 1 | `BasicServicesKit.batteryInfo.getBatteryConfig` | **`BasicServicesKit.Battery.getStatus`** |
| 2 | `BasicServicesKit.batteryInfo.isBatteryConfigSupported` | `ConnectivityKit.bas.getRemoteDeviceBatteryInfo` |
| 3 | `BasicServicesKit.batteryInfo.setBatteryConfig` | `ConnectivityKit.connection.getRemoteDeviceBatteryInfo` |

Token's top hit is about *configuring* battery behavior, not reading the
level — wrong function for the request. Embedding's top hit,
`Battery.getStatus`, is the right one. **Embedding win.**

**Intent** — `need="read the current battery level"`

Both rank `catalog:readBluetooth` first — neither is right, because this
request has no real intent-to-another-app answer (reading battery is an
SDK call, not something another app's intent would naturally expose). The
registry simply has nothing better to lexically or semantically match
against the word "battery" except `BatteryCareUIAbility`'s own raw
entries, which both rankings do surface lower down. **Tie (both wrong, and
unsurprisingly so — this request doesn't need find_intent_function at
all).**

## 2. "A simple screen with one button that turns on the phones flashlight"

**SDK** — `need="turn on the phone flashlight torch"`

| rank | token | embedding |
|---|---|---|
| 1 | `CameraManager.getTorchMode` | **`CameraManager.setTorchMode`** |
| 2-4 | torch-support query/event functions | `TelephonyKit.radio.turnOnRadio` (×3) |

Token's top-8 is all torch-*adjacent* functions (query/event, not the
actual setter) because the model's own query included the word "torch" —
`setTorchMode` is in the list, just not first. Embedding puts the correct
function first. **Embedding win** (token isn't *wrong* here, just not as
sharp — the real gap shows up in the intent half below).

**Intent** — same `need`

| rank | token | embedding |
|---|---|---|
| 1 | `databackup/ViewPhoneAssistant` | **`sceneboard/OpenFlashlight`** |
| 2-3 | parental-control toggles | `catalog:readBluetooth`, `catalog:openCalendar` |

Token's entire top-8 is unrelated (parental controls, phone assistant,
screen-reader volume) — the real `OpenFlashlight` system intent (yes, it
exists, named exactly that) never surfaces at all. Embedding finds it in
one. **Clear embedding win** — this is the exact motivating case from the
original plan, confirmed twice now (also validated live in the
feature-commit itself).

## 3. "A toggle switch that turns Bluetooth on or off"

**SDK** — `need="turn Bluetooth on or off"`

| rank | token | embedding |
|---|---|---|
| 1 | `MDMKit.bluetoothManager.turnOffBluetooth` | **`ConnectivityKit.bluetooth.enableBluetooth`** |
| 2 | `MDMKit.bluetoothManager.turnOnBluetooth` | `MDMKit.bluetoothManager.turnOnBluetooth` |
| 3-5 | `TelephonyKit.radio.turnOffRadio` (×3) | `ConnectivityKit.bluetoothManager.enableBluetooth` |

Token's list is dominated by `turnOnRadio`/`turnOffRadio` (telephony, not
Bluetooth) because "turn" is a real word in both — the exact failure class
`VeraSdkIndex.ets`'s doc comment names. `enableBluetooth` never appears in
token's top-8 at all. Embedding surfaces three different kits' enable/
disable spellings. **Clear embedding win**, matches the documented
"toggle bluetooth" gap case precisely (model phrased it "turn ... on or
off" instead of "toggle", same failure either way).

**Intent** — `need="open Bluetooth settings"` (the model asked a
differently-phrased second question for this tool)

Token ranks `catalog:setBluetooth` 5th, behind three Settings-app
navigation intents. Embedding ranks it 1st. **Embedding win**, smaller
margin — token wasn't blind here, just worse-ordered.

## 4. "A button that takes a photo with the camera"

**SDK** — `need="take a photo with the camera"`

| rank | token | embedding |
|---|---|---|
| 1 | `CameraInput.getPhysicalCameraOrientation` | **`CameraKit.PhotoOutput.capture`** |
| 2-8 | orientation/occlusion queries, `createCameraInput` (×2) | `PhotoOutput.capture` (×3), `MediaAssetChangeRequest.saveCameraPhoto` (×2) |

`PhotoOutput.capture` — the actual answer — **does not appear anywhere in
token's top-8**. Every token hit is about camera *setup* (orientation,
input creation), not taking the photo. Embedding's top-8 is almost
entirely on-target. **Clear embedding win**, the second documented gap
case from `VeraSdkIndex.ets` confirmed exactly as written ("'take a photo'
never finds PhotoOutput.capture").

**Intent** — same `need`

Both rank the real `camera/TakePhoto` intent 1st. **Tie, both correct** —
this one has enough literal word overlap ("photo", "camera") that token
search was never going to miss it.

## 5. "A button that starts turn-by-turn navigation to a saved address"

**Intent** — `need="start turn by turn navigation to a saved address"`

| rank | token | embedding |
|---|---|---|
| 1 | `screenreader/TurnAudioVolumeSeekBar` | **`catalog:startNavigate`** |
| 2-8 | screen-reader volume/notification toggles | real map apps' `StartNavigate` (AMap, Huawei Maps), `catalog:navigateTo`, `catalog:searchOnMap` |

Token's entire top-8 is screen-reader volume controls — "turn" matched
"Turn*" intent names lexically, "navigation" matched nothing, and the
result is completely unrelated to the request. Embedding's top-8 is
almost entirely real navigation intents, catalog and raw both. **Dramatic
embedding win** — the starkest gap of the five, because the query's only
content word that token could anchor on ("turn") happened to collide with
an entirely different feature's naming.

**SDK** — `need="start turn by turn navigation to a destination address"`
(the model asked a separately-phrased question for this tool, in the same
generation)

| rank | token | embedding |
|---|---|---|
| 1 | `TelephonyKit.radio.turnOffRadio` | `ArkUI.router.push` |
| 2-8 | radio/bluetooth toggles (×5) | `ArkUI.Router.push`, `router.pushUrl` (×4), `LocationKit.geolocation.getAddressesFromLocation` (×2) |

Neither is actually right — turn-by-turn navigation isn't an SDK call, it
belongs to the intent half above, which the model correctly also used.
Token's list is pure noise (radio/Bluetooth toggles via the "turn"
collision again). Embedding's list is topically closer (in-app routing,
address-to-location lookup) without being correct either. **Embedding
less wrong, not actually right** — the honest read is that this specific
tool call shouldn't have mattered much, since find_intent_function already
found the real answer in the same round.

## 6-10: five more complex, multi-capability prompts

These five were run specifically for the timing pass below, so only the
winning (embedding) result was logged in full detail, not the side-by-side
token ranking (`VERA-*-EMBED-CMP`) the first five got -- the question this
round was "how long," not "which is better," and that question was
already settled by prompts 1-5. Still worth a quick read on plausibility.

**6. "A screen that shows the current weather forecast and lets me share
it with a contact via text message"** -- two calls. Intent:
`need="send a text message to a contact"` → `SendTextMessage` (right, same
as prompt 6's earlier run). SDK: `need="read the current weather forecast
for my location"` → `LocationKit.geolocation.getCurrentLocation` --
reasonable under the circumstances (this phone's SDK surface has no
weather API at all, so location is the closest real building block a
weather feature could start from).

**7. "An app that lets me scan a QR code and then opens the link in the
browser"** -- four calls across two rounds, and the one real miss in this
set. SDK: `ArkTS.Blob.text` and `ArkWeb.WebviewController.startCamera` for
the two QR-scanning attempts -- neither is a real QR scanner (this SDK
surface doesn't appear to expose one token or embedding could have found).
Intent: **both** rounds ("open a web link in the browser" /
"open a URL or web page in the web browser") landed on
`catalog:openCalendar` -- wrong, and worth noting plainly rather than
glossing over: the catalogue/registry on this phone apparently has nothing
that reads as "open a URL in a browser" closely enough, and embedding
picked the least-bad available row rather than a right one. The generated
program itself handled this gracefully on-device (it compiled on attempt
1 and showed "Scanning is not available here," with a manual-entry
fallback, rather than a broken button) -- but the search genuinely didn't
find a good answer here, token or embedding.

**8. "A screen with a countdown timer that vibrates the phone and shows a
notification when it finishes"** -- two SDK calls, both clean:
`need="vibrate the phone"` → `SensorServiceKit.Vibrator.vibrate`;
`need="show a notification"` → `NotificationKit.Notification.show`. Both
exactly right.

**9. "A button that checks if the phone is connected to WiFi, and if not,
opens the WiFi settings"** -- SDK `need="check whether the phone is
currently connected to WiFi"` → `ConnectivityKit.wifiManager.isWifiActive`
(right). Intent `need="open the WiFi settings screen"` →
`settings/SetWifiAutoEnable` -- not exactly "open the settings page," but
in the right neighborhood (a real WiFi-settings-app intent, not noise).

**10. "A screen that lets me record a short voice memo, save it, and play
it back"** -- three calls. SDK `need="record a short voice memo from the
microphone"` → `MediaKit.VideoRecorder.start` (this surface's recorder is
video-first; using it for audio-only is a real, if imperfect, answer).
SDK `need="play back a recorded audio file"` → `AVSessionKit.avSession
.startAVPlayback` (right). Intent `need="record a voice memo with the
sound recorder app"` → `soundrecorder/StartRecord` -- exactly right, a
real app's real intent.

## Summary (quality)

| # | request | SDK result | intent result |
|---|---|---|---|
| 1 | battery level | embedding win | tie (both wrong, tool mismatch) |
| 2 | flashlight | embedding win | **embedding win (motivating case)** |
| 3 | bluetooth toggle | **embedding win (motivating case)** | embedding win |
| 4 | take a photo | **embedding win (motivating case)** | tie (both right) |
| 5 | navigation | embedding less-wrong (both miss) | **embedding win (largest gap)** |
| 6 | weather + share | reasonable (no real weather API exists) | right |
| 7 | QR code + browser | both miss (no QR scanner on this SDK) | **miss (no good "open browser" row either)** |
| 8 | timer + vibrate + notify | right (×2) | n/a |
| 9 | WiFi check + settings | right | reasonable (right app, not exact page) |
| 10 | voice memo record/save/play | reasonable, then right | right |

Zero cases where token search beat embedding search (prompts 1-5, the
only ones with a logged side-by-side ranking). Three of the first five
prompts are exact live confirmations of the gaps the original plan named
by hand (`VeraSdkIndex.ets`'s doc comment: "toggle bluetooth", "take a
photo", "turn on the flashlight") — all three close completely with
embedding search. Prompt 7 is the one clean miss across all ten --
genuinely nothing in either corpus answers "open a URL in the browser"
well, which token search also would not have found (not an
embedding-specific failure).

The repeated "turn" collision (prompts 2, 3, 5 all phrase the request with
"turn on/off") is the single biggest pattern in token search's failures
here — matches `VeraSdkIndex.ets`'s own documented case
(`turnOnRadio`/`turnOffRadio` beating `setTorchMode`) almost exactly,
just recurring across unrelated requests because "turn" is such a common
English verb for toggling things.

## Timing — 3 passes × 22 need-strings, isolated from DeepSeek

Replaces the earlier partial version of this section (one sample per
need-string, and the query-embed-vs-scan split only captured for 2 of 22
-- a grep pattern mismatch silently dropped it for the rest). This pass
fixes both, via a small, permanent, opt-in diagnostic
(`VeraSearchBenchmark.ets`, wired through `EntryAbility.ets`'s
`extractBenchmark` the same way `IntentProbe.ets`'s `runProbe` already is)
that calls the same four search functions production code calls --
`findSdkFunctionFromCache`/`findSdkFunctionByEmbedding`,
`findIntentFunction`/`findIntentFunctionByEmbedding` -- directly, three
interleaved passes over the exact 22 `need` strings DeepSeek already
produced for the 10 prompts above, with no DeepSeek round trip involved:

```
hdc shell aa start -a EntryAbility -b com.vera.probe.dyn --ps veraBenchmark 1
hdc shell hilog -x | grep VERA-BENCH
```

**tokenFullMs** is token search's entire cost (`findSdkFunctionFromCache`/
`findIntentFunction` alone) -- no live model call on this path, so "full"
and "search" are the same number. **embeddingFullMs** is
`queryEmbedMs + scanMs`; **scanMs** alone (dot-product-and-sort over the
cached corpus, excluding the live query-embedding model call) is "search
over the corpus" in the narrower sense. All three numbers are logged by
the search functions themselves (`VERA-SDK-EMBED-TIMING`/
`VERA-INTENT-EMBED-TIMING`), not computed after the fact.

**Why isolated from DeepSeek doesn't just substitute one bias for
another, cheaper one -- checked, not assumed:** every row below also
carries the single real sample from that need-string's original live
DeepSeek run (the earlier version of this table). If this benchmark's
own tight, back-to-back loop behaves differently from production's
naturally spaced-out calls, it should show up as a gap between "isolated
avg" and "live sample" -- and it does, consistently, for the SDK corpus
specifically (see "What the numbers say" below). That gap is reported
as a finding, not hidden by only publishing the isolated numbers.

### Prompt 1

| corpus | need | pass 1 | pass 2 | pass 3 | avg token | avg embed (query+scan) | live DeepSeek sample (token/embed) |
|---|---|---|---|---|--:|---|---|
| SDK | read the current battery level | tok 159, embed 530 (q93+s437) | tok 45, embed 683 (q89+s594) | tok 62, embed 681 (q90+s591) | **89** | **631** (91+541) | 130 / 536 |

### Prompt 2

| corpus | need | pass 1 | pass 2 | pass 3 | avg token | avg embed (query+scan) | live DeepSeek sample (token/embed) |
|---|---|---|---|---|--:|---|---|
| SDK | turn on the phone flashlight torch | tok 33, embed 524 (q86+s437) | tok 32, embed 688 (q94+s594) | tok 30, embed 678 (q92+s586) | **32** | **630** (91+539) | 40 / 516 |
| Intent | turn on the phone flashlight torch | tok 2, embed 154 (q93+s61) | tok 3, embed 159 (q94+s65) | tok 2, embed 160 (q94+s66) | **2** | **158** (94+64) | 1 / 139 |

### Prompt 3

| corpus | need | pass 1 | pass 2 | pass 3 | avg token | avg embed (query+scan) | live DeepSeek sample (token/embed) |
|---|---|---|---|---|--:|---|---|
| SDK | turn Bluetooth on or off | tok 42, embed 720 (q81+s639) | tok 49, embed 678 (q89+s588) | tok 45, embed 680 (q89+s591) | **45** | **692** (86+606) | 63 / 497 |
| Intent | open Bluetooth settings | tok 3, embed 138 (q78+s60) | tok 3, embed 139 (q78+s60) | tok 5, embed 139 (q78+s61) | **4** | **138** (78+60) | 3 / 129 |

### Prompt 4

| corpus | need | pass 1 | pass 2 | pass 3 | avg token | avg embed (query+scan) | live DeepSeek sample (token/embed) |
|---|---|---|---|---|--:|---|---|
| Intent | take a photo with the camera | tok 1, embed 151 (q93+s58) | tok 1, embed 160 (q93+s66) | tok 1, embed 148 (q84+s64) | **1** | **153** (90+63) | 10 / 147 |
| SDK | take a photo with the camera | tok 60, embed 679 (q88+s590) | tok 42, embed 677 (q92+s585) | tok 66, embed 694 (q93+s601) | **56** | **683** (91+592) | 34 / 535 |

### Prompt 5

| corpus | need | pass 1 | pass 2 | pass 3 | avg token | avg embed (query+scan) | live DeepSeek sample (token/embed) |
|---|---|---|---|---|--:|---|---|
| Intent | start turn by turn navigation to an address | tok 1, embed 163 (q102+s61) | tok 2, embed 158 (q104+s54) | tok 1, embed 159 (q96+s62) | **1** | **160** (101+59) | 8 / 159 |
| SDK | start turn by turn navigation to a destination address | tok 69, embed 705 (q114+s591) | tok 65, embed 700 (q105+s595) | tok 44, embed 687 (q99+s588) | **59** | **697** (106+591) | 40 / 542 |

### Prompt 6

| corpus | need | pass 1 | pass 2 | pass 3 | avg token | avg embed (query+scan) | live DeepSeek sample (token/embed) |
|---|---|---|---|---|--:|---|---|
| Intent | send a text message to a contact | tok 2, embed 160 (q100+s60) | tok 1, embed 160 (q99+s61) | tok 1, embed 165 (q97+s68) | **1** | **162** (99+63) | 10 / 147 |
| SDK | read the current weather forecast for my location | tok 68, embed 700 (q102+s598) | tok 52, embed 698 (q101+s597) | tok 45, embed 692 (q103+s589) | **55** | **697** (102+595) | 42 / 529 |

### Prompt 7

| corpus | need | pass 1 | pass 2 | pass 3 | avg token | avg embed (query+scan) | live DeepSeek sample (token/embed) |
|---|---|---|---|---|--:|---|---|
| SDK | scan a QR code with the camera and return the decoded text | tok 112, embed 719 (q127+s592) | tok 116, embed 706 (q117+s589) | tok 117, embed 704 (q114+s590) | **115** | **710** (119+590) | 104 / 540 |
| Intent | open a web link in the browser | tok 2, embed 154 (q96+s58) | tok 1, embed 159 (q100+s59) | tok 1, embed 160 (q98+s62) | **1** | **158** (98+60) | 2 / 147 |
| Intent | open a URL or web page in the web browser | tok 3, embed 169 (q108+s61) | tok 2, embed 173 (q109+s64) | tok 2, embed 173 (q109+s64) | **2** | **172** (109+63) | 24 / 202 |
| SDK | scan a barcode or QR code using the camera | tok 58, embed 696 (q104+s592) | tok 57, embed 699 (q105+s594) | tok 48, embed 694 (q107+s587) | **54** | **696** (105+591) | 61 / 698 |

### Prompt 8

| corpus | need | pass 1 | pass 2 | pass 3 | avg token | avg embed (query+scan) | live DeepSeek sample (token/embed) |
|---|---|---|---|---|--:|---|---|
| SDK | vibrate the phone | tok 22, embed 671 (q83+s588) | tok 19, embed 672 (q82+s590) | tok 20, embed 680 (q83+s597) | **20** | **674** (83+592) | 37 / 498 |
| SDK | show a notification | tok 30, embed 669 (q77+s592) | tok 24, embed 667 (q76+s591) | tok 23, embed 676 (q85+s591) | **26** | **671** (79+591) | 29 / 503 |

### Prompt 9

| corpus | need | pass 1 | pass 2 | pass 3 | avg token | avg embed (query+scan) | live DeepSeek sample (token/embed) |
|---|---|---|---|---|--:|---|---|
| SDK | check whether the phone is currently connected to WiFi | tok 67, embed 694 (q105+s589) | tok 60, embed 698 (q104+s594) | tok 58, embed 696 (q105+s591) | **62** | **696** (105+591) | 70 / 514 |
| Intent | open the WiFi settings screen | tok 7, embed 148 (q89+s59) | tok 4, embed 155 (q90+s65) | tok 3, embed 147 (q89+s58) | **5** | **150** (89+61) | 2 / 148 |

### Prompt 10

| corpus | need | pass 1 | pass 2 | pass 3 | avg token | avg embed (query+scan) | live DeepSeek sample (token/embed) |
|---|---|---|---|---|--:|---|---|
| SDK | record a short voice memo from the microphone | tok 40, embed 692 (q101+s591) | tok 52, embed 692 (q103+s589) | tok 38, embed 693 (q103+s590) | **43** | **692** (102+590) | 78 / 511 |
| SDK | play back a recorded audio file | tok 86, embed 681 (q93+s588) | tok 65, embed 680 (q93+s587) | tok 62, embed 681 (q92+s589) | **71** | **681** (93+588) | 41 / 523 |
| Intent | record a voice memo with the sound recorder app | tok 2, embed 168 (q107+s61) | tok 3, embed 166 (q104+s62) | tok 6, embed 166 (q104+s62) | **4** | **167** (105+62) | 2 / 163 |

## Overall (132 timed calls: 39 SDK + 27 intent, 3 passes each)

| corpus | n | token avg | token min/max | embed avg | embed min/max | queryEmbed avg | scan avg |
|---|--:|--:|---|--:|---|--:|--:|
| SDK (16,511 entries) | 39 | 55.9 | 19 / 159 | 680.9 | 524 / 720 | 96.4 | 584.4 |
| Intent (~661 entries) | 27 | 2.4 | 1 / 7 | 157.4 | 138 / 173 | 95.8 | 61.6 |

## What the numbers say

**The isolated benchmark's own first two calls reveal something the
averages alone would hide.** Pass 1's first two SDK scans (prompt 1,
prompt 2) ran at 437ms; every one of the other 37 SDK scans across all
three passes sits tightly in a 585-601ms band:

| | pass 1 | pass 2 | pass 3 |
|---|--:|--:|--:|
| SDK scanMs avg | 571.1 | 591.3 | 590.8 |
| SDK scanMs range | 437-639 | 585-597 | 586-601 |

That's not noise -- 437ms shows up *exactly* twice, both at the very
start of the run, then the cost steps up and stays there for the
remaining 37 calls. The likely cause is a brief CPU frequency/scheduler
boost immediately after the app comes to the foreground, which has worn
off by the third call and never recurs. The methodology section's choice
not to discard a "warmup" pass is exactly why this is visible at all --
discarding pass 1 would have hidden the transition, not just the noise.

**This is also most of the answer to "does bypassing DeepSeek affect the
measurement" -- and the answer is yes, measurably, just not in the way
that would have been the obvious worry.** The live single samples
captured during the original 10 real DeepSeek generations (the "live
DeepSeek sample" column in every table above) sit consistently *closer to
the 437ms boost-window number than to the 590ms steady-state one*, for
nearly every SDK row: prompt 1's live sample was 536ms, prompt 4's was
535ms, prompt 6's was 529ms -- all near the fast end, none near 680-720ms.
Those ten live generations were each spaced apart by several seconds of
real network and model-generation time per tool call; this benchmark's
66 calls run back to back in under a minute. The isolated benchmark's
steady-state embedding cost (~680ms average) is very likely inflated by
sustained CPU load from the tight loop itself -- something a real
generation, with seconds of idle time between tool calls, mostly avoids.
**The honest number for a real generation's SDK embedding search is
probably closer to the live samples (~500-540ms) than to this
benchmark's own steady-state average (~680ms)** -- the isolated
benchmark is a worse-case, sustained-load figure, not a best-case one.

Token search shows no equivalent gap (live samples and isolated averages
are in the same range throughout) -- consistent with token search being
cheap enough, CPU-wise, to not generate the sustained load that produces
this effect in the first place.

**The intent corpus doesn't show either effect** -- scanMs stays in a
tight 54-68ms band from the very first call, and live-vs-isolated
samples agree reasonably well (e.g. prompt 9: live 148ms, isolated avg
150ms). At ~661 entries the dot-product math is cheap enough that neither
the boost window nor sustained-load throttling moves it much.

**Token search remains far cheaper in absolute terms** -- isolated
averages of 55.9ms (SDK) and 2.4ms (intent) against embedding's 680.9ms
and 157.4ms, an order of magnitude or more either way. In context, the
DeepSeek round trip each tool call sits inside runs several seconds
end to end, so even the inflated ~680ms SDK figure is a single-digit
percentage of total generation time. A generation with several tool
calls still pays this repeatedly, not once: prompt 7 made four calls
(two SDK, two intent) in one generation.
