# vera-probe-dynamic

Measures the VERA runtime on a real HarmonyOS device, as a **dynamic**-ArkTS
port. Paired with `webview-probe`, which loads the same two prompts as HTML
into a WebView — same device, same OS build, same clock.

## Why a dynamic port exists

The `'use static'` original (`../vera-probe`) will not run on either device
available:

| device | blocker |
|---|---|
| SGT-AL00, API 22 | SDK 26 emits Panda bytecode 0.1.0.7; the VM accepts ≤ 0.0.0.5 |
| Mate 60 Pro, API 26 | SDK 26.0.0.26 is ABI-incompatible with the device's 26.0.0.37 |

Dynamic ArkTS tolerates both skews — `webview-probe` is dynamic and ran fine on
the API 22 phone. Building for API 26 requires a private environment, so the
target is **API 22**, which is also where the WebView numbers already come from.

## What this does and does not establish

**Does:** a real device measurement of the VERA pipeline — parse, VM boot,
`render()`, decode, ArkUI construction, and resident memory — directly
comparable to the WebView cost measured on the same phone.

**Does not:** measure the runtime the VERA product targets. Static ArkTS runs on
the Panda static VM (`modules_static.abc`); dynamic ArkTS runs on the
ArkCompiler JS-style engine (`modules.abc`). These are different runtimes, and
the host measurement of 435 µs parse+boot was taken on the static one. So these
numbers must not be blended with the host static figures — quote them as the
dynamic-ArkTS device cost, and treat the static-vs-dynamic gap as the remaining
open question.

## The port

`entry/src/main/ets/vera/` is a mechanical port of the static runtime in
`vera-static-hello` — same algorithm and control flow, only the type system
differs:

| static | dynamic |
|---|---|
| `'use static'` | removed |
| `final class` | `class` |
| `int`, `double` | `number` |
| `Any` | `Object \| null \| undefined` |
| `x instanceof number` | `typeof x === 'number'` |
| `Int.toDouble(a & b)` | `a & b` — JS bitwise already yields a number |
| `JSON.parseJsonElement` | `JSON.parse` — the JsonElement API does not exist here |

`parseConstant` was rewritten rather than translated. The static version handled
only null, string, boolean, number and `BytecodeFunction`, so array and plain
object constants fell through to `Unsupported constant value`. That gap is now
closed. **This is not known to be the cause of the `pairs` failure** seen on the
real runtime: that artifact contains no container constants at all (16 numbers,
43 strings, 1 boolean, 8 functions), so that bug is still unexplained.

The port compiles clean (`status: ok`, 0 diagnostics) but **has not yet been run
on a device**, so its output has not been checked against the reference
implementation. First run should confirm the rendered tree matches what
`vera-bench` produces on the host before any timing is quoted.

## Running it

```bash
./build-hap.sh      # builds and signs; finds the UDID itself
./measure.sh 3      # 3 cold reps per program -> results/device.jsonl
```

Sign with `--mode debug` for API 22. On an API 26 device AppGallery installs a
disposed rule against debug-signed sideloaded apps and AMS refuses the launch;
`--mode release` yields `os_integration`, which its risk control leaves alone.

## What it measures

| metric | from |
|---|---|
| `parseUs` | `parseBytecodeAssembly(vbc1)` |
| `bootUs` | `new VeraVM(program)` + `run()` |
| `renderUs` | `invokeFunction('render')` |
| `decodeUs` | `decodeVeraUi` — validation and UI-node decode |
| `coldTotalUs` | the four above, first pass, nothing warm |
| `warmTotalUs` | same pipeline, mean of 100 iterations |
| `buildUs` | state write to ArkUI `onAppear`: the construction term |
| `pssDeltaKb` | `hidebug.getPss()` before vs after |

Timing uses `getUptime(TimeType.STARTUP, true)` — nanoseconds. The phases are
microsecond-scale, so millisecond resolution would floor them all to zero.

The programs are the exact artifacts the benchmark scored, compiled to vbc1 and
embedded as literals so the timed region has no network and no file I/O:
`tictactoe` (6557 B) and `dashboard` (1439 B) from `results/cortex5`.
