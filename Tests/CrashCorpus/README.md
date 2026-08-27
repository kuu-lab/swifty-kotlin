# Crash corpus

This directory stores minimized Kotlin inputs that exercise the mutation
fuzzer's process-safety oracle. Each `.kt` file may have a same-basename
`.expect` sidecar with one of these expectations:

- `no-crash`: compilation may succeed, emit an ordinary diagnostic, or emit an
  explicit `KSWIFTK-ICE-*` diagnostic, but it must not signal, time out, or fail
  silently.
- `clean`: compilation must exit successfully.
- `diagnostic`: compilation must exit with visible non-ICE diagnostics.
- `ice`: compilation must exit with a `KSWIFTK-ICE-*` diagnostic.

The JSON sidecar emitted by `Scripts/mutate_diff_cases.py` records the seed,
mutation, and observed process result for triage. Only reviewed, minimized
reproductions should be promoted into this directory.

The initial entry is a diagnostic-only parser plumbing sample. It is not a
known compiler bug and does not assert a crash; the first real finding should
be added with its focused regression fix according to `AGENTS.md`.
