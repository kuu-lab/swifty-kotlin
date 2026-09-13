---
name: Swifty-Kotlin Sema Refactor Verification
description: Choosing a proportionate verification gate for a test-only Sema consolidation PR in swifty-kotlin — which suites actually cover the change, and why the full diff_kotlinc directory belongs in CI rather than an interactive session.
---

# Swifty-Kotlin Sema Refactor Verification

## Devin Secrets Needed
None.

## When to use

The PR touches only `Tests/CompilerCoreTests/Sema/*.swift`, or adds a small source fix for
Sema lookup, and the question is "did the refactor preserve behaviour" rather than "does
this new feature work". The goal is a gate that is proportionate: the front end has a
suite that covers all of Sema, and reaching for the whole-repo diff gate instead costs
tens of minutes without covering anything more.

Command syntax, environment variables, and golden-update flags are in
[`CLAUDE.md`](../../../CLAUDE.md) and [`AGENTS.md`](../../../AGENTS.md).

## Standard gate

```bash
bash Scripts/swift_test.sh --filter SmokeTests   -Xswiftc -swift-version -Xswiftc 6
bash Scripts/swift_test.sh --filter CompilerCoreTests -Xswiftc -swift-version -Xswiftc 6
bash Scripts/validate_runtime_abi_links.sh -Xswiftc -swift-version -Xswiftc 6
```

- `CompilerCoreTests` covers every Sema and front-end suite, `AnnotationSemanticTests`
  included. A narrower regex over the specific suites you touched is fine for iteration,
  but the target-wide run is what proves a consolidation didn't drop a case.
- `validate_runtime_abi_links.sh` is a thin wrapper that `exec`s `swift_test.sh` with
  `--filter RuntimeABIExternalLinkValidationTests` and forwards `"$@"`, which is why the
  language-mode flags work on it.
- `-Xswiftc -swift-version -Xswiftc 6` is what [`CLAUDE.md`](../../../CLAUDE.md)
  recommends for matching CI. `Package.swift` already sets `swiftLanguageModes: [.v6]`, so
  it is belt-and-braces rather than load-bearing; the flags CI adds that a local run does
  not are `-Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency`
  (`.github/workflows/ci.yml`).
- Add `swift package clean` before building **only** if a source change appears to have no
  effect — SwiftPM skips re-linking when a checkout leaves source mtimes older than the
  binary. It is a several-minute cost, not a default step.

## Scoping `diff_kotlinc.sh`

`bash Scripts/diff_kotlinc.sh Scripts/diff_cases` is a CI-sized gate: ~1425 `.kt` cases
across `DIFF_WORKERS` (default: CPU count), typically 30+ minutes, with no output until
cases complete. Delegate it to CI or a dedicated long runner.

Interactively, run a subset covering the API surfaces the PR actually changed:

```bash
mkdir -p "${TMPDIR:-/tmp}/diff_subset"
cp Scripts/diff_cases/{duration,math,native,property,random,range,uuid,string}*.kt \
  "${TMPDIR:-/tmp}/diff_subset/"
DIFF_RUN_TIMEOUT=30 bash Scripts/diff_kotlinc.sh "${TMPDIR:-/tmp}/diff_subset"
```

Pick the prefixes from the changed declarations, not from this list — it is an example of
the shape, not a fixed set.

A test-only Sema consolidation usually needs no `diff_kotlinc.sh` run at all: it cannot
change emitted code. Run it when the PR also carries a source fix to Sema lookup or
overload resolution, since that can change which declaration a call site binds to — and
whenever the PR is RF-tagged, where [`CLAUDE.md`](../../../CLAUDE.md)'s refactor gate
mandates the full directory regardless. Delegate that run; don't wait on it.
