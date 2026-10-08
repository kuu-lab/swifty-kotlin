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

Run the runner's API-independent regressions with:

    python3 Scripts/js_annotations/test_run_candidate.py

The regression uses a fake candidate compiler and traps java/kotlinc on PATH to
confirm the reference tools are not launched.
