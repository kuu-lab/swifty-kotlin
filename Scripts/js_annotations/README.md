# js_annotations candidate-only runner

run_candidate.py executes the audited fixture's native-compat lane with
kswiftc only. It reads docs/fixtures/js_annotations/expectations.json without
changing it and never invokes kotlinc, java, or another JVM reference. Cases
outside native-compat (for example, JS emission and consumer checks) are listed
as out-of-lane and are not counted as candidate passes.

## Run

Build the local compiler, then run a specific fixture or all native-compatible
fixtures:

    swift build --jobs 1
    python3 Scripts/js_annotations/run_candidate.py --case native_observations
    python3 Scripts/js_annotations/run_candidate.py

The runner builds one candidate stdlib artifact inside its run directory, then
uses it for the fixtures. Compile and run timeouts default to 60 and 10 seconds;
the stdlib build timeout defaults to 600 seconds. Override them with
--compile-timeout, --run-timeout, and --stdlib-timeout. Pass --kswiftc to use
another compiler binary or --stdlib-library to provide an existing .kklib with
manifest.json.

## Expectations and lanes

The adapter accepts schema version 1 from the audit JSON. It selects cases with
both the native-compat lane and a nativeContract. It verifies the source SHA-256,
then compares compile exit code and the multiset of diagnostic severity/kind
pairs. The compiler's -Xdiagnostics json output supplies candidate diagnostic
codes; diagnostic_map.json contains only mappings verified against KSwiftK's
diagnostic registry. An unmapped candidate code or expected diagnostic kind is
a failure. Runtime exit code, stdout, and stderr are compared byte-for-byte to
the native contract. Compile-only diagnostics fixtures do not run.

The audit currently labels the native contract as
required-by-followup-not-yet-implemented; the runner still executes it and
reports concrete candidate failures. It does not convert pending
implementation, a missing expectation, or a timeout into a skip or pass.
KUU-1613 can add verified annotation diagnostic mappings in this JS-specific
adapter as the compiler codes become available.

## Saved evidence

Each invocation creates a unique directory under
.artifacts/js_annotations_candidate_only/. summary.json records the lane,
selected/excluded cases, compiler and Swift toolchain identity, expected and
actual outcomes, and failure reasons. Each case directory retains the exact
source, compile and run commands, stdout/stderr bytes, process exit/timeout
status, mapped diagnostics, and result.json. The candidate stdlib build also
retains its command and output. SwiftPM and Clang module caches are redirected
to this invocation's module-cache directory, so the runner does not write to a
shared user cache. Reruns create new directories rather than overwriting
previous evidence.

## Source injection / `.kklib` O0/O2 matrix (KUU-1616)

Run the full audited annotation, collection-view, and reflection native-compat
contract matrix from the repository root. The default includes both
`expectations.json` and `views-expectations.json`, with each fixture set's own
diagnostic map:

    swift build --jobs 1
    python3 Scripts/js_annotations/run_matrix.py \
      --stdlib-timeout 1800 \
      --record-summary docs/fixtures/js_annotations/evidence/native-matrix-results.json

The matrix runner always creates a new `KSwiftKStdlib.kklib` under its unique
`.artifacts/js_annotations_matrix/<run-id>/` directory. It does not accept an
existing library path. The same compiler binary and generated artifact are used
for all four cells:

| Stdlib path | Consumer optimization |
|---|---|
| `--stdlib-from-source` | `-O0`, `-O2` |
| Fresh `.kklib` via `--no-stdlib --stdlib-library <run artifact>` | `-O0`, `-O2` |

Every native-compat fixture is checked against its audited `nativeContract`:
compile exit code and diagnostic severity/kind counts, then runtime exit code,
stdout, and stderr where applicable. Unknown diagnostic codes, missing
expectations, timeouts, mode-to-mode differences, and metadata sentinel drift
are failures. The complete matrix pins marker diagnostics, generic nullable view
values, typed-unbound receiver/generic metadata for `createInstance`, bound
callable-reference identity, constructor selection, and default argument
evaluation. Duplicate cases shared by the two contract files are run once while
retaining both expectation sources. Use repeatable `--case <id>` only for a
focused rerun; omit it for the full matrix and its sentinel checks. For custom
contract sets, repeat `--expectations` and `--diagnostic-map` once per pair.

`summary.json` and each cell's `result.json`, exact commands, stdout/stderr, and
fixture source are saved under the run directory. The summary binds the fresh
artifact tree and manifest hashes to the compiler binary SHA-256, Git revision,
compiler-source-tree SHA-256, and hashes of both expectation files and diagnostic
maps. `--record-summary` writes the portable matrix evidence alongside the
audited fixtures. It records the run ID and artifact-run directory relative to
the evidence file, so the exact build command and per-cell outputs can be found
in that run's `summary.json` and case directories. The runner also verifies
the compiler and source snapshot did not change while the matrix ran. Portable
evidence uses repository-relative paths and labels external inputs by basename.

For a focused rerun after changing a fixture or compiler path, keep a separate
evidence file and artifact run directory. For example, the corrected unbound
`createInstance` fixture is recorded with:

    python3 Scripts/js_annotations/run_matrix.py \
      --case unbound_create_instance \
      --case reflection \
      --case native_observations \
      --stdlib-timeout 1800 \
      --record-summary docs/fixtures/js_annotations/evidence/<focused-run>.json

KUU-1616's captured full run is `native-matrix-results.json` (108 cells: 56
passed, 52 failed). All 27 fixtures have matching outcomes across the four
matrix cells, with no source/artifact or O0/O2 divergence; three out-of-lane
cases are excluded. The 52 failures are expected-contract mismatches or
unmapped diagnostic codes in 13 fixtures whose native contracts are still
marked `required-by-followup-not-yet-implemented`. The full run includes the
KClass constructor-property fix and corrected unbound fixture source. The
post-fix, fresh-artifact four-cell result for the focused annotation/reflection
fixtures passed 12/12 across
`unbound_create_instance`, `reflection`, and `native_observations`. The run
summaries under `.artifacts/js_annotations_matrix/<run-id>/` retain each
compiler and artifact identity and all per-cell command/output files.

Relevant environment details (`KSWIFTK_LLVM_DYLIB`, `LD_LIBRARY_PATH`, include
and library paths, and Apple SDK overrides when set) are captured in the
summary. Build the compiler first. A cold full-source `.kklib` build may exceed
ten minutes before it emits an artifact, so the default stdlib-build timeout is
30 minutes. Runner regressions can be exercised independently with:

    python3 Scripts/js_annotations/test_run_matrix.py

Run the runner's API-independent regressions with:

    python3 Scripts/js_annotations/test_run_candidate.py

The regression uses a fake candidate compiler and traps java/kotlinc on PATH to
confirm the reference tools are not launched.

## Daily CI and KUU-1480 handoff (KUU-1617)

Build an optimized CompilerCore first for the complete matrix, then use the
same entrypoint as the nightly CI job:

    KSWIFTK_OPTIMIZE_COMPILER_CORE=1 swift build --product kswiftc
    KOTLINC=/not-used JAVA_BIN=/not-used python3 Scripts/js_annotations/run_ci.py \
      --kswiftc .build/out/Products/Debug/kswiftc

Use `.build/debug/kswiftc` for a native SwiftPM build layout. The entrypoint runs
three runner/aggregation regression scripts, then all 27 native fixtures through
the complete four-cell matrix. It accepts no case filter or existing artifact.
Evidence is kept under `.artifacts/js_annotations_ci/<unique-run>/`:
`inputs.json` (Python/runner hashes, current diff-case snapshot identity, CI run URL),
`runner-results.json`, exact regression process logs, `matrix-results.json`,
`evidence.md/json`, and the matrix's full build/compile/runtime outputs. Nonzero
exit is preserved for failures, timeouts, incomplete matrices, and stale inputs.
The aggregator explicitly distinguishes `fail`, `timeout`, and `not-run`; it
never treats out-of-native-lane fixtures as candidate passes.

PR/merge-queue `ci.yml` runs the three fast regression scripts in Repository
checks. `nightly-full.yml` runs `verify-js-annotations` daily and on manual
workflow dispatch, using its checked release compiler artifact and a fresh
stdlib build. The matrix job fails on mismatches and uploads evidence even on
failure. Its job summary links the original observations through the
[KUU-1480 handoff](../../docs/js-annotations-ci-evidence.md). It does not require JVM
reference setup. Saved evidence is retained for 30 days; preserve the run URL and
artifact when passing the result to KUU-1480.

To inspect saved matrix evidence without rerunning the compiler:

    python3 Scripts/js_annotations/summarize_evidence.py \
      --matrix docs/fixtures/js_annotations/evidence/native-matrix-results.json \
      --output /tmp/js-annotations-saved-evidence.md

This returns failure for the existing 52 failed cells and marks runner
regressions not-run unless `--runner-results <run>/runner-results.json` is
supplied. It is a historical aggregation, not a current compiler validation.
