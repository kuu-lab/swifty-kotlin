# kotlinx-io 0.9.1 API coverage inventory

This directory contains the KUU-1726 source/ABI/test ledger and a reproducible
generator. It is intentionally isolated from KUU-1727's test harness.

## Pinned inputs

- Upstream repository: `Kotlin/kotlinx-io`, tag `0.9.1`, immutable commit
  `362bdc35e159bad6da1e08101c8321792d762281`.
- Kotlin compiler baseline: `2.3.10`.
- The checked-in `upstream/kotlinx-io-0.9.1/` snapshot includes all tracked
  Kotlin source files under the core and bytestring source sets, their four
  public API dumps, and the upstream license. `upstream-lock.json` records
  each file's Git blob SHA-1, byte length, and SHA-256.
- `upstream-tests-index.json` records upstream common/native/Apple/JVM test
  file paths, commit blob IDs, byte lengths, and discovered test names. Its
  own SHA-256 is pinned in `upstream-lock.json`.
- The JVM artifacts are pinned by Maven coordinate and SHA-256 in the same
  lock file:
  - `org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1`
  - `org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1`

## Outputs

- `api-inventory.tsv` has one row per KLIB declaration, JVM public ABI entry,
  or `@PublishedApi` implementation declaration. The KLIB source declaration
  and JVM ABI are different representations. JVM file facades, companion
  classes, fields, default bridges, property accessors, mangled functions,
  and bridge methods are classified separately from Kotlin source callables.
- `platform-scope.tsv` records platform-source roots, explicit Apple KLIB
  target markers, and the in-scope/target-out rationale. Common declarations
  remain in scope even when compiled for JS, Wasm, Android Native, Linux, or
  MinGW. Apple and JVM interop surfaces remain in scope.
- `inventory-summary.md` gives generated counts, current owner routing, and
  reproducibility notes.

Each API/ABI row records its signature, declaration kind, source/API-vs-ABI
classification, default-parameter count where the KLIB dump exposes it,
source annotations, deprecation level, declared exception documentation,
source and test references, local declaration/test candidates, status, and
owner issue. `missing` means no exact declaration with the same Kotlin owner,
receiver and parameter types was found. `unverified` means a declaration exists or the row is a
generated JVM ABI entry; this inventory does not claim behavioral verification.
Only dedicated behavior tests can advance a row to `verified`.

The KLIB dump is the authority for Kotlin source API signatures. Kotlin 2.3.10
PSI parses declaration ownership, receiver/parameter types, visibility, defaults,
annotations and KDoc. JVM Kotlin metadata links each exact owner/name/descriptor
to its source declaration, including `@JvmName`, getter/setter and field roles.
The declaration catalogs pin all upstream/local Kotlin inputs, runtime sources,
extractor hashes and compiler/metadata jar hashes. Test names are linked to pinned upstream
test-file hashes. Suite references are explicitly labelled when no test name
could be matched. `@PublishedApi`/internal declarations that appear in the
KLIB dump have their own representation and are not counted as public source
APIs.

Owner routing uses existing KUU child issues for Buffer/Segment (KUU-1729),
buffered source/sink and lifecycle (KUU-1730), primitive/ByteArray I/O
(KUU-1731), and UTF-8 (KUU-1733). ByteString, Filesystem, JVM interop, and
Apple-only APIs have dedicated children KUU-1760, KUU-1761, KUU-1762 and KUU-1763.
`local_implementation_refs` records source bodies and explicit runtime bridges;
`local_contract_differences` records parameter name, visibility and default
presence differences. The known ByteStringBuilder append default gap is assigned
to KUU-1760. `platform_metadata` retains each exact declaration's annotations,
defaults and contracts, so JVM actual annotations do not disappear behind common
declarations. Public JVM exception typealiases retain their Java target types.

The generator has negative guards for Okio-only `ByteString.hex()`,
`Buffer.snapshot(byteCount)`, and `select`; it preserves the real zero-argument
`Buffer.snapshot()` and kotlinx-io hex conversion functions.

## F01 consumer matrix

KUU-1820 consumers are generated from the pinned KLIB source rows and their
source declaration catalog:

```sh
python3 Scripts/io_api_inventory/generate_f01_consumers.py --write
python3 Scripts/io_api_inventory/generate_f01_consumers.py
python3 Scripts/io_api_inventory/test_f01_consumers.py
```

`f01_consumers/positive-common.kt` gives each non-deprecated common source
signature typed arguments and calls it with full and omitted-default argument
lists. `positive-apple.kt` and `positive-platform.kt` retain the target-specific
signatures in separate consumers. `positive-jvm.kt` is the subset paired with a
JVM ABI declaration; it is suitable for comparison with the pinned Kotlin 2.3.10
compiler and 0.9.1 JVM artifacts. This split matters for expect/actual exception
constructors and Foundation APIs, which are not all present in the JVM artifact.

The generated negative consumers cover ledger deprecations, every direct IO
opt-in marker row, all `@PublishedApi internal` rows, and the inventory's
Okio-only negative guards. Those intentionally absent API names and their
upstream absence basis are recorded in `negative-api-guards.tsv`; the generator
reads that ledger and includes its rows in `consumer-manifest.json`.
`negative-opt-in-warning.kt` and
`negative-opt-in-error.kt` split opt-in levels so upstream Kotlin diagnostics
remain observable even when error diagnostics would suppress warnings in a
combined compile. `consumer-manifest.json` records the ledger IDs and source
scopes. Regeneration fails if a public source row is missing from the positive
scope consumers or an invalid guard is missing from the negative consumer.

## F02 executable and independent-process matrix

F02 consumers turn the 235 JVM-paired common source rows into actual calls with
fresh typed inputs. Both full and default calls have required completion events.
Return values include primitive type identity and floating-point wire bits;
ByteString/array/buffer/builder contents, exception types and callback counts are
observed. Unsafe contexts remain inside their original callback scope, and all
four unchecked-write widths are committed and checked. The producer exports
typed probes; the independent consumer creates arguments and invokes those
imported signatures. The compile-only F01 consumers are not execution evidence.

```sh
python3 Scripts/io_api_inventory/generate_f02_consumers.py --write
python3 Scripts/io_api_inventory/generate_f02_consumers.py
python3 Scripts/io_api_inventory/test_f02_matrix.py
python3 Scripts/io_api_inventory/run_f02_matrix.py \
  --compiler .build/debug/kswiftc --output /tmp/new-f02-run \
  --kotlin-home /path/to/kotlinc-2.3.10 --java /path/to/java21/bin/java \
  --dependencies /path/to/locked-io-jars --compile-timeout 1800
```

The default selection also runs every `kotlinx_io*.kt` diff consumer in a batch,
the existing compound Buffer/buffering/numeric/EOF fixtures, and the public Apple
SDK fixture plus 25 original Apple bodies. Explicit `--case ledger-jvm` selects only that subset. Each selected
case has source, explicit bundled stdlib and independent `.kklib` producer/consumer
lanes at O0/O2. Selected cases are batched to avoid recompiling the whole bundled
source stdlib for each small fixture; `--separate-cases` gives individual lanes.
The locked reference compiler is Kotlin 2.3.10; candidate stdlib artifacts use
KSwiftK's product language version, currently 2.4.20.
`--entry-point` selects the intended qualified consumer entry and
preserves other fixture mains. Producer source paths are retired before the
consumer process starts; producer/consumer cwd, temporary directories and
incremental/stdlib caches are distinct.

The deprecated `Path.source()` / `Path.sink()` compatibility consumer is
available independently as `--case deprecated-path-source-sink`. It compares
the pinned JVM output against source, fresh bundled-stdlib, and independent
producer/consumer lanes at O0/O2, including explicit return typing, pending
sink writes, source read-ahead, and the documented file-error types.

KUU-2596's internal `Segment.dataAsByteArray` probe runs only its six lanes,
checks unsuppressed Kotlin internal visibility on both compilers, and checks
the pinned JVM method's `(Z)[B` descriptor and public/final/synthetic flags:

```sh
python3 Scripts/io_api_inventory/run_f02_matrix.py \
  --case segment-data-as-byte-array \
  --separate-cases \
  --compiler .build/debug/kswiftc --output /tmp/kuu-2596-f02 \
  --kotlin-home /path/to/kotlinc-2.3.10 --java /path/to/java21/bin/java \
  --dependencies /path/to/locked-io-jars
```

Every selected lane is attempted after a lane failure, and each failure retains
its raw diagnostic or output difference. The original Apple test module is run
separately: its test-only helpers occupy real stdlib packages and can conflict
with ordinary bundled declarations. Its failed lanes remain required failures
in the overall result; isolating it does not remove it from the selection.
The batch driver catches an unexpected Kotlin exception per fixture/group,
records an `UNHANDLED-*` event and continues the remaining consumers. Such an
event differs from the reference bytes and fails the lane; it cannot become a
passing result merely because the driver itself exits zero. Fatal native traps
still stop the process and remain incomplete execution. Original fixture bodies
are preserved.

The boundary fixture additionally checks dependency initialization order/once,
inline/default/accessor imports, thrown callbacks, and a retained callback and
Java IO adapter after `System.gc()`. The matrix preserves raw output, commands,
deadlines, exits, binary/stdlib/producer/source/resource hashes and workspace SHA.
Only owned execution directory prefixes are normalized during comparison; all
other bytes remain exact. Reference SDK files and IO jars must match the fixed
lock. By default the stdlib is freshly built in this run; supplying an explicit
`--stdlib-library` records that its freshness was not inferred from its path.

`SELECTED_MATRIX_PASS` means only the selected scenarios passed. The manifest
retains every unpaired source/platform/internal/JVM ABI row, and `issue_complete`
remains false: compilation, native bridge behavior and JVM bytecode descriptor
presence are different obligations. EOF and public Apple fixtures retain their
declaration-derived expected-output classification, rather than being described
as new official Native reference runs. Other boundary/resource/annotation
contracts and the parent's full upstream execution gate remain separate checks.

### F02 pre-rebase acceptance snapshot, 2026-10-14

KUU-1822 remains incomplete. The full pre-rebase run used retrieved master
`01544852e570d6bb1766e44b4e9fb47af88121f2` plus the uncommitted F02 changes,
compiler SHA-256 `058faee4af259a74b65023f5721233b97d86b3ac2eb6928827b7fa525aee25e7`,
and a new CLI stdlib build. Its 1,848 relative file/SHA-256 entries have digest
`a60d5de95ccbfc647a65603faca90aa99c26e2da1f0b1f4e669c315eb222dad8`
(SHA-256 of UTF-8 compact JSON with sorted keys); all file hashes and 439 Runtime
object hashes are retained. The Runtime object cache was manifest-validated;
this is not a claim of a clean Runtime rebuild.

The complete selection attempted all 12 lanes: **0 PASS, 12 FAIL, no timeout**.
The ordinary batch's six lanes compiled, linked and ran with all 235 ledger rows,
275 full/default calls, 50 fixture endings and eight case endings. Five groups
(library boundary, Buffer, buffering, EOF and numeric contracts) matched their
classified reference bytes in all six lanes. The previous producer-only null
results in 12 calls disappeared at O0/O2. All nine Base64 ledger rows now match
in all six lanes, and the FQN Base64/object initialization probes match the fixed
JVM reference at O0/O2. Those improvements do not make the full lanes pass.

Remaining failures include unexpected fixture termination on closed raw streams,
Apple partial writes, Any-based raw-bit/name observations and the original Apple
module's Sema failures. JVM/Native closed-stream exception and temporary-directory
differences require platform-specific reference classification. General compiler
blockers are tracked as KUU-2055, KUU-2057, KUU-2069, KUU-2151 and KUU-2152;
the existing Apple partial-write owner is KUU-2150. No official Kotlin/Native
reference execution was performed, and no ledger row was promoted to verified.

Validation was limited to `swift build`, the related Swift gate (59 tests before
the additional FQN correction), the final singleton regression (one test with six
source/artifact/producer O0/O2 cases), eight inventory reproducibility tests and
ten runner tests. Whole Swift/Golden/diff suites were not run. The attempted broad
LibraryStdlibCallTests run was interrupted and is not passing evidence.

Local raw evidence is in `/private/tmp/kuu1822/final-master-matrix/` and
`/private/tmp/kuu1822/final-master-auxiliary-probes/`: summaries, original streams,
commands, deadlines, exits, file hashes, event checks and byte differences.
Linear KUU-1822 records the immutable run details and blocker links.

[Draft PR #8937](https://github.com/kuu-lab/swifty-kotlin/pull/8937) is based on
retrieved master `d23b45f21ca8c6b4e90bc9d558c12d2bd0fe8692`, including the
existing `usePinned` and `Mutex(locked)` fixes. It preserves compact indexed
metadata and passes `swift build` after adapting the singleton initialization
helper call. The PR and Linear issue record the subsequent focused gate and
fresh-artifact matrix results separately from the pre-rebase evidence above.

## Recheck

Requires Python 3.9+ and no third-party Python package:

```sh
python3 Scripts/io_api_inventory/generate.py --write
python3 Scripts/io_api_inventory/generate.py --check
python3 Scripts/io_api_inventory/generate.py --check --verify-jars /path/to/jar-directory
python3 Scripts/io_api_inventory/test_reproducibility.py
python3 Scripts/io_api_inventory/refresh_source_index.py --kotlin-home /path/to/kotlinc --jars-dir /path/to/jar-directory --check
```

The final command expects the two pinned jars named either as full Maven file
names or as `kotlinx-io-core-jvm.jar` and `kotlinx-io-bytestring-jvm.jar`.
`--download-jars` can fetch them from Maven Central where network access is
available; every downloaded artifact is SHA-256 checked before success.

### Per-row validation evidence

`api-validation-evidence.json` is an independent, versioned input to the
generator. Add one record per API `row_id`; do not promote `status` by editing
`api-inventory.tsv`. Schema v2 keeps the upstream-catalog evidence route and
adds a registered local-probe route. Schema v1 records remain readable as
upstream-catalog records. To get the current implementation/test hashes,
required obligations, and exact execution lanes for a row, run:

```sh
python3 Scripts/io_api_inventory/generate.py --show-input-hashes klib-4d280feb368bb149
```

Each record stores the tested candidate commit SHA, the pinned upstream tag and
commit, both input hashes, its exact compatibility obligations, and one or more
execution records. Each execution has a `case_id`, `lane`, and separate
reference/candidate `execution_id`, `result`, and `exit_code`. A row is rendered
as `verified` only if every required lane has a passing reference and candidate
result with exit code zero.

Schema v2 records set `evidence_source` to `upstream-catalog` or `local-probe`.
The upstream route retains the locked JVM/Native execution catalog checks. The
local route accepts only case IDs registered in `generate.py`, mapped to that
row's exact `local_test_refs`, allowed evidence methods, and required lanes.
Local results also state their `method`; their deterministic execution IDs bind
the candidate SHA, pinned reference commit, case ID, lane, and side. The F02
summary includes these records under `local_probe_executions`. For the JVM ABI
row, the pinned reference is checked by JVM reflection and the candidate side
checks the local declaration's source metadata, since KSwiftK emits native
artifacts rather than JVM bytecode.

Local evidence must cover every registered case and every lane for that row.
For `Segment.dataAsByteArray`, native rows require both the backing-view probe
and the cross-module visibility probe in all six native lanes; the JVM ABI row
requires the descriptor reflection probe and local source-metadata assertion.
The `SystemTemporaryDirectory` row has a dedicated Kotlin consumer for source
and fresh-KLIB O0/O2 value, type, and identity assertions, plus JVM reflection
for the pinned field owner, descriptor, flags, value, and singleton identity.
The local probes' bytes and the referenced upstream tests remain part of the
row's test input hash, so edits invalidate prior evidence.

The obligations follow the ledger representation: JVM ABI rows require only
`jvm-descriptor`. Other rows require both `native-source` and `native-bridge`.
The native-source obligation covers `source-O0`, `source-O2`,
`stdlib-library-O0`, and `stdlib-library-O2`; the native-bridge obligation
covers `producer-consumer-O0` and `producer-consumer-O2`. A paired JVM ABI row
does not inherit native results, and a source row does not inherit JVM
descriptor evidence.

The generator rejects unknown or duplicate row IDs, malformed hashes, a
different reference pin, stale implementation/test inputs, non-passing or
unrun executions, duplicate cases, and missing or unrelated lanes. Upstream
case IDs must be referenced by that row's upstream tests, and both execution
IDs must map to the same case in the locked JVM and Native execution catalogs.
Local case IDs must match the reviewed probe registry and the row's local test
references. A manual status edit is discarded when outputs are regenerated.
`--write` changes only the three generated ledger output files and reads the
evidence file without rewriting it. `--check` verifies upstream snapshots, the
test index lock, negative guards, evidence, any execution catalogs used by
evidence, and byte-for-byte output without modifying files.

```sh
python3 Scripts/io_api_inventory/test_validation_evidence.py
```

The relocation regression copies inputs into a different checkout root in
reverse filesystem creation order and compares all three generated outputs.
PublishedApi row identities use upstream-relative paths, and local references
are sorted. Kotlin golden and diff fixtures participate in the test index,
alongside Swift tests; references match complete symbol tokens and are candidate
coverage, not evidence of passing tests or overload-specific assertions.

Refreshing the declaration catalogs requires the pinned Kotlin 2.3.10 SDK,
Java and both 0.9.1 jars. Use the final command with `--write` after intentionally
changing a local source input or extractor. It updates the two catalogs and
their SHA-256 entries in `upstream-lock.json`; then regenerate the ledger.
Normal `generate.py --check` uses only Python and rejects changed catalog/input
hashes. The relocation regression includes Kotlin and runtime implementation
inputs and compares all three ledger outputs.

The ledger is an inventory, not a behavioral completion claim. No row is
automatically `verified`; upstream execution and candidate behavior tests belong
to KUU-1727 and the implementation children. A test reference is a candidate
mapping or labelled suite reference, not evidence that the test ran or that its
assertions cover that overload. Full integration remains owned by KUU-1725.
