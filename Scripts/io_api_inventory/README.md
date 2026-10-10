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
owner issue. `missing` means no same-kind, same-name declaration was found by
the local source scan. `unverified` means a candidate exists or the row is a
generated JVM ABI entry; this inventory does not claim behavioral verification.
Only dedicated behavior tests can advance a row to `verified`.

The KLIB dump is the authority for Kotlin source API signatures; source matches
are references and metadata support. Test names are linked to pinned upstream
test-file hashes. Suite references are explicitly labelled when no test name
could be matched. `@PublishedApi`/internal declarations that appear in the
KLIB dump have their own representation and are not counted as public source
APIs.

Owner routing uses existing KUU child issues for Buffer/Segment (KUU-1729),
buffered source/sink and lifecycle (KUU-1730), primitive/ByteArray I/O
(KUU-1731), and UTF-8 (KUU-1733). ByteString, Filesystem, JVM interop, and
Apple-only APIs stay routed to KUU-1725 for triage/splitting because the
current child list has no dedicated owner for those families.

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
```

The final command expects the two pinned jars named either as full Maven file
names or as `kotlinx-io-core-jvm.jar` and `kotlinx-io-bytestring-jvm.jar`.
`--download-jars` can fetch them from Maven Central where network access is
available; every downloaded artifact is SHA-256 checked before success.

`--write` changes only the three generated output files in this directory.
`--check` verifies all upstream snapshot hashes, the test index lock, negative
guards, and byte-for-byte deterministic output without modifying files.

The relocation regression copies inputs into a different checkout root in
reverse filesystem creation order and compares all three generated outputs.
PublishedApi row identities use upstream-relative paths, and local references
are sorted. Kotlin golden and diff fixtures participate in the test index,
alongside Swift tests; references match complete symbol tokens and are candidate
coverage, not evidence of passing tests or overload-specific assertions.

## Remaining inventory audit work

KUU-1726 remains in progress. The current name-based matcher does not distinguish
receivers, owners and parameter types, so its `missing`/`unverified` counts are
provisional. For example, Apple and ByteBuffer declarations can be linked to
different existing overloads; overload-specific exception contracts can be
borrowed from the first same-name declaration. JVM `@JvmName` correspondence,
internal visibility and extension PublishedApi signatures also need correction.
Gap families routed to KUU-1725 need dedicated child issues. Reproducible
generation does not establish these audit criteria.
