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

The generator's `--write` changes only the three generated ledger output files.
`--check` verifies all upstream snapshot hashes, the test index lock, negative
guards, and byte-for-byte deterministic output without modifying files.

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
