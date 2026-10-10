# kotlinx-io upstream test matrix

This directory contains a strict paired-run harness for cases from the pinned
`kotlinx-io` 0.9.1 sources. It is separate from the stdlib API ledger and from
`Scripts/diff_kotlinc.sh`, whose cases are compiler-authored programs rather
than upstream test IDs.

## Runner contract

`run_matrix.py` takes a JSON manifest. Each `run` case has one reference and
candidate command, each as an argv array (no implicit shell). The command gets
`KIO_CASE_ID`, `KIO_UPSTREAM_ID`, `KIO_PLATFORM`, `KIO_SIDE`, `KIO_REPO_ROOT`,
and `KIO_ARTIFACT_DIR`. Arguments may use `{repo}`, `{source}`, `{case_id}`,
`{upstream_id}`, `{platform}`, `{side}`, and `{artifact_dir}` placeholders.

Each command writes exactly one JSON object to stdout. The harness requires
these fields and compares the full object:

```json
{
  "stdout": "program output",
  "exception_type": null,
  "bytes_consumed": 0,
  "buffer_state": null,
  "byte_buffer_state": null,
  "callbacks": null,
  "resource_lifecycle": null
}
```

Put compiler/test-runner diagnostics on stderr. A timeout is `HANG`; a nonzero
exit is `CRASH`; malformed protocol data is `ERROR`; unequal observations are
`DIFFERENCE`. Explicit `skip`, `unsupported`, and `unmapped` dispositions and
declared `expected_failure` results are retained as separate non-pass counts.
The command exits 0 only when every selected case is `PASS`, exits 2 when the
matrix is incomplete, and exits 1 for a test/protocol failure. Thus an empty
selection or a suite containing only skips cannot look green.

Each invocation writes `summary.json`, `summary.md`, one `cases/<id>/result.json`
per case, and the exact stdout/stderr of each side to a unique run directory
under `.artifacts/kotlinx_io_upstream/` by default. The summary records pinned
versions, host/runtime information, repository SHA/dirty state, and counts by
classification for CI artifact upload.

## Actual JVM reference suite

`run_jvm_reference.py` compiles the original common/JVM test and sample sources
against the fixed 0.9.1 jars and Kotlin 2.3.10. JUnit Platform runs each concrete
factory class, including inherited methods, original assertions, temporary
folders and cleanup hooks. The source files, SDK files and dependencies must
match `reference-lock.json`; altered upstream assertions are rejected.

```sh
python3 Scripts/kotlinx_io_upstream/prepare_reference.py \
  --target jvm --output /tmp/kio-reference-environment
python3 Scripts/kotlinx_io_upstream/run_jvm_reference.py \
  --upstream /tmp/kio-reference-environment/upstream \
  --kotlin-home /tmp/kio-reference-environment/installation/kotlinc \
  --java /path/to/java21/bin/java \
  --dependencies /tmp/kio-reference-environment/dependencies \
  --output /tmp/kio-reference-results
```

The audited JVM catalog contains 1,403 concrete executions covering all 651
eligible source function IDs in 50 compiled files. Discovery must match every
execution ID in `jvm-executions.expected.json`, so losing a test or a factory
cannot silently reduce coverage. Results also retain skipped, failed and missing
executions, and failed test containers cause failure. Compiler and execution
timeouts terminate the subprocess group. Java 21 is selected explicitly for
both the Kotlin compiler and the test runner.

Each run saves version output, exact commands, source/dependency/runner hashes,
the discovered IDs, per-execution results and an `execution-map.json` linking
concrete classes to their declaring method, source ID and blob hash. A local
reference run compiled all 50 files and passed all 1,403 executions. Its results
are **reference-only**: the summary records 1,403 candidate `UNMAPPED` cases
and zero paired passes. The upstream assertions check expected exceptions,
byte/buffer state, callbacks and lifecycle, but the JUnit runner does not export
those successful internal observations as a paired-run protocol object.

## Actual Native reference suite

`run_native_reference.py` compiles unchanged sources to a test KLIB, then links
the official Kotlin/Native test runner. On Linux this includes 34 common files
and the native actual helper. On macOS it also includes all eight Apple files.
The locked catalog contains 1,188 common executions and 29 Apple executions.
Generated test IDs, runtime discovery and TeamCity execution events must all
match the selected catalog. Failures, skips and unfinished executions cannot
become passes. A local Linux run passed all 1,188 common executions.

```sh
python3 Scripts/kotlinx_io_upstream/prepare_reference.py \
  --target macos_arm64 --output /tmp/kio-native-environment
python3 Scripts/kotlinx_io_upstream/run_native_reference.py \
  --target macos_arm64 --upstream /tmp/kio-native-environment/upstream \
  --kotlin-home /tmp/kio-native-environment/installation/kotlin-native-prebuilt-macos-aarch64-2.3.10 \
  --compiler-archive /tmp/kio-native-environment/downloads/kotlin-native-prebuilt-macos-aarch64-2.3.10.tar.gz \
  --java /path/to/java21/bin/java --konan-data /tmp/kio-konan-data \
  --dependencies /tmp/kio-native-environment/dependencies \
  --output /tmp/kio-native-results
```

Use `macos_x64` with its x86_64 compiler on Intel Macs. `paths.json` records the
exact installed paths. The runner requires the requested target to match its
host, selects Java 21 explicitly, verifies the compiler archive and every
installed regular SDK file, and records Xcode/macOS SDK versions on macOS.
IO, coroutines and atomicfu main/cinterop KLIBs have fixed SHA-256 hashes.
LLVM/libffi/LLDB toolchain dependencies downloaded by Kotlin/Native on a clean
host are not pre-pinned here: the run records their actual content fingerprint.
With a populated cache, `--offline` disables compiler dependency downloads.
`TMPDIR` always points to a writable per-run directory, preserving the original
upstream tests and assertions.

The Native result is also **reference-only**: candidate executions are UNMAPPED
and paired passes are zero. `.github/workflows/kotlinx-io-reference.yml` runs the
JVM suite and the common/Apple suite on the actual macOS runner architecture,
and uploads raw logs, commands, hashes, discovery and execution maps even on
failure. A local Linux success does not establish Apple or macOS success.

## Source inventory and remaining execution coverage

`coverage-map.seed.json` contains 684 test/sample function IDs from 61 pinned
source files, plus seven inventory-only helpers. A source function ID is distinct
from a concrete execution ID: inherited factories expand one source function
into multiple executions, while loops retain all their original parameter values
inside the unchanged test body. The JVM execution catalog records this expansion.
The seed map's local test references remain unverified and cannot be counted as
paired passes. Regenerate it with:

```sh
python3 Scripts/kotlinx_io_upstream/import_inventory.py \
  --test-index /path/to/io_api_inventory/upstream-tests-index.json \
  --api-inventory /path/to/io_api_inventory/api-inventory.tsv \
  --upstream-lock /path/to/io_api_inventory/upstream-lock.json \
  --output Scripts/kotlinx_io_upstream/coverage-map.seed.json
```

Apple tests require the macOS CI execution. The seed paired matrix includes all
680 applicable common/Apple/JVM function IDs as unmapped until assertion-preserving
candidate adapters exist. Four Windows-only IDs are explicitly unsupported.
No Apple reference success is claimed by the JVM or Linux result.

KSwiftK ports preserving every original upstream assertion body and their
paired observation adapters remain unfinished. Existing `kotlinx_io_*` diff cases
and Swift integration tests provide local coverage, but do not yet establish
that mapping. KUU-1727 remains incomplete until those adapters and macOS
reference execution are verified. Run the focused harness checks with:

```sh
python3 -m unittest discover -s Scripts/kotlinx_io_upstream/tests -v
```
