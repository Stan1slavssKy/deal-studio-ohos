# Working on this repo

A HarmonyOS app that generates small programs from a plain-English prompt,
compiles them on the phone and renders them as native ArkUI. `entry/src/main/
ets/vera/` is the language: compiler, VM, the `std/ui` catalogue and the theme.
`entry/src/main/ets/components/VeraPreview.ets` is the renderer.

## Before you build: find out what is missing, then ask

For a rebuild and in-place update, run `./update-phone.sh` directly: it checks
the tools and the installed app before building. Do not repeat the checks below
or reread the build scripts on routine update requests unless the command fails.

For other build workflows, check the external tools first — this prints what
it found and what it did not:

```bash
bash -c 'source ./tool-paths.sh
printf "%-18s %s\n" hvigorw "$(vera_hvigorw 2>&1)"
printf "%-18s %s\n" OHOS_BASE_SDK_HOME "$(vera_sdk_home 2>&1)"
for t in arkui-sign arkui-device-cli; do
  printf "%-18s %s\n" "$t" "$(vera_kit_bin "$t" 2>&1)"; done
printf "%-18s %s\n" hdc "$(vera_hdc_dir 2>&1)"
printf "%-18s %s\n" hapsigner "$(vera_hapsigner 2>&1)"'
```

Set tool locations in the shell environment, never in scripts or documentation.
Export both `OHOS_BASE_SDK_HOME` and `DEVECO_SDK_HOME` with your SDK root, and
add your SDK toolchains and command-line-tools `bin` directories to `PATH`.

| what | used for | required environment configuration |
|---|---|---|
| **Hvigor 7.26.0.static** | builds with `createHapTask` | required `HVIGORW` naming the absolute path to the 7.26.0.static wrapper; invoked with `bash`, never resolved from `PATH` |
| **Build SDK 26.0.0** | compile SDK; the build profile targets `26.0.0` | `OHOS_BASE_SDK_HOME` and `DEVECO_SDK_HOME`, both naming existing SDK directories; exported by the builder |
| **ArkTS Agent Kit** | unchanged `arkui-sign` debug signing and `arkui-device-cli` screen dumps; updater retains both preflight checks | tools on `PATH`, or `KIT_ROOT` containing `tools/`, `.venv/bin/` or `bin/` |
| **hdc** | everything that talks to the phone | SDK toolchains directory on `PATH`, or `HDC_DIR` naming the directory containing `hdc` |
| **hapsigner** | unchanged `sign-system.sh` calls `dist/hap-sign-tool.jar`; needs a JRE | `HAPSIGNER` naming the directory containing `dist/` |

`OHOS_TOOLCHAINS` optionally prepends an additional toolchains directory for
measurement. There are no machine-specific installation path defaults.

One more thing is not in this repo and is not checked by that command:
**llama.cpp**, under `entry/src/main/cpp/llama.cpp` (git-ignored). Fetch the commit
pinned in `entry/src/main/cpp/CMakeLists.txt` -- the exact commands are in the
comment at its top. Without it the build still succeeds but produces a stub with
no model support: embedding search for SDK functions and intents falls back to
keywords, and the Generate and Chat screens say so in their status line. After
fetching it, delete `entry/.cxx` once so CMake sees it.

**If any of them prints an ERROR line, stop and ask the person working with you
— do not guess a path and do not install anything.** Ask exactly this:

> This repo needs Hvigor, the OpenHarmony SDK, the ArkTS Agent Kit, hdc and
> hapsigner, and I cannot find *(name the ones that failed)*. Where are they on
> this machine? Please configure `HVIGORW`, `OHOS_BASE_SDK_HOME` and
> `DEVECO_SDK_HOME`, `KIT_ROOT` or `PATH`, `HDC_DIR` or `PATH`, and `HAPSIGNER`
> as appropriate. I will use these environment settings without storing paths
> in scripts or documentation.

An explicitly set variable is an instruction, not a hint: if the thing is not
where it says, the script fails and names the variable rather than quietly using
another copy.

## Building, signing, installing

For routine updates:

```bash
./update-phone.sh
```

This requires exactly one connected phone and an existing system installation
with the same bundle name. It runs the clean build below, skips debug signing,
signs once with the system profile, installs without deleting anything, and verifies
that the app ID, UID and first install time did not change while update time
advanced. On any error, stop: never uninstall, clear app data, or change the
bundle name to work around an update failure. The script prints elapsed time.

`build-hap.sh` validates and exports `OHOS_BASE_SDK_HOME` and `DEVECO_SDK_HOME`,
then invokes Hvigor from the repository root. Export `HVIGORW` with the absolute
path to your Hvigor 7.26.0.static wrapper; it never selects a wrapper from `PATH`:

```bash
bash "$HVIGORW" clean --mode module -p module=entry -p product=default createHapTask --analyze=normal --parallel --incremental --no-daemon
```

`createHapTask` depends on `assembleHap`
and renames the output to
`entry/build/default/outputs/default/vera-probe-dyn-unsigned.hap`. The builder
shows Hvigor output directly, stops on a nonzero exit or missing artifact, and
copies the HAP to `${HAP_OUT_DIR:-/tmp/vera-probe-dyn-hap}`. This is a clean
build despite the `--incremental` flag. Do not restore the `arkui-hvigor`
wrapper or expect its JSON status/diagnostics protocol.

For separate build/sign steps:

```bash
./build-hap.sh --unsigned
./sign-system.sh
hdc install /tmp/vera-probe-dyn-hap/vera-probe-dyn-system-signed.hap
./measure.sh 3
```

Without `--unsigned`, `build-hap.sh` keeps its original debug-signing behaviour
and finds the UDID itself. It cannot produce a system app: `arkui-sign` takes no
profile argument and reads the kit's own template. A program that calls
`std/intent` needs system signing because `insightIntentDriver` is a system API.

For shell-only changes, run:

```bash
for script in build-hap.sh sign-system.sh update-phone.sh tool-paths.sh; do
  bash -n "$script" || exit
done
git diff --check
```

No shell lint/typecheck command is configured; use ShellCheck if it is available.

## Three traps that cost real time

**Never `hdc uninstall`.** It destroys `{filesDir}/vera`: every saved project,
every program's state and the DeepSeek API key. There is no backup route. If an
install is refused, work out why instead — and note that a normal app cannot be
updated into a system app in place (`9568294 apptype not same`), so a bundle that
has ever been installed normally has to be built under a throwaway `bundleName`
to test a system profile.

**The API key is a launch parameter**, never compiled in, and it survives
restarts once stored:

```bash
hdc shell aa start -a EntryAbility -b com.vera.probe.dyn --ps deepseekKey sk-...
```

The same goes for `vera-server`, if the Server generation mode is wanted:
`--ps veraServer http://host:port`. Neither has a default, and neither belongs
in the source.

**Prompts typed into the Generate screen are written in English**, even when the
conversation is not.

## Checking things without a device

The ArkTS build leaves plain TypeScript in
`entry/build/default/cache/default/default@CompileArkTS/esmodule/release/entry/src/main/ets/vera/`,
so the compiler, the VM, the UI decoder and the theme all run under node on the
host. That is the fast way to check a change: seconds, no install, no
generation. Two things to know — imports come out as
`"@normalized:N&&&entry/src/main/ets/vera/X&"` and must be rewritten to
`"./X.js"`, and `compileVeraSource` **throws** `CompileError` carrying
`.diagnostics` rather than returning them.

For anything visual, render a proof sheet rather than waiting on a generated app
to happen to contain the thing you changed: a hand-built node tree in the
renderer, or an SVG rasterised on the host. Chasing a layout bug through
minute-long generations does not converge — that mistake has been made here.

## Where the pieces are

| file | what it is |
|---|---|
| `entry/src/main/ets/vera/VeraUiCatalog.ets` | the one description of `std/ui`: components, styles, icons, composition rules. The compiler interface, the validator and the model's prompt are all generated from it |
| `entry/src/main/ets/vera/VeraTheme.ets` | six presets, light and dark, and every colour and size the renderer uses |
| `entry/src/main/ets/vera/VeraIcons.ets` | sixteen icons as path data, normalised to one optical size |
| `entry/src/main/resources/rawfile/vera-skill.txt` | the prompt, with `{{UI_CATALOG}}` spliced in |
| `docs/demo-prompts.md` | the prompts this is demonstrated with, and what to check in the output |
| `docs/prompts/intent-coverage.md` | 59 prompts that between them reach 596 of the 640 intents this phone has, each with the addresses it should pull in and a table to record what the phone actually did. `tools/prompt-coverage.py` checks it against the pulled `insight_intent.db` on the host — run that before editing a prompt, because the wording is what decides which addresses the model is shown |
| `docs/prompts/block-composition.md` | prompts for the composed blocks (record_log and the readers that take their data from its ports), the layout and blocks each should give, and a column for what the phone did. Blocks, ports, layouts, holes and the composition record are in `VeraTemplates.ets`, `VeraLayouts.ets`, `VeraHoles.ets`, `VeraComposition.ets`; host checks are `tools/vera-harness/{ledger,itinerary,composition,hole,port-bind,section-pick}-check.js` |
| `docs/examples/shanghai-layover.vera` | a program the model actually wrote, kept verbatim |
| `docs/intent-call-contract.md` | `intent.call`'s signature and its four-shape answer contract (JSON / `"ok"` / `"declined code=N"` / `"error N: ..."`), with two confirmed device cases of generated code checking for `"ok"` or not checking at all — read before touching a handler that reports success or failure |

Adding a component means editing the catalogue, adding a case in
`VeraUi.ets`, and adding a branch in `VeraPreview.ets` — the compiler, the
validator and the prompt follow from the catalogue on their own. The renderer
keeps a second hardcoded list of kinds it can draw and complains on startup if
it drifts from the catalogue.
