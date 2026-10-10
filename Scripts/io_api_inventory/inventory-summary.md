# kotlinx-io 0.9.1 API inventory

Upstream: [`Kotlin/kotlinx-io@362bdc35e159bad6da1e08101c8321792d762281`](https://github.com/Kotlin/kotlinx-io/tree/362bdc35e159bad6da1e08101c8321792d762281) (tag `0.9.1`).
Kotlin compiler baseline: `2.3.10`.

## Generated counts

- Kotlin/KLIB source declaration rows: **281**.
- JVM ABI dump rows: **369**, including **124** generated/accessor rows kept separate from Kotlin source callables.
- KLIB rows backed by non-public implementation declarations: **34**; these are separate from public source APIs.
- `@PublishedApi internal` implementation ABI rows: **19**.
- Rows marked missing because no exact owner/receiver/parameter local declaration was found: **57**.
- Rows with exact local declarations or generated ABI entries, without semantic verification: **649**.
- Public JVM exception typealiases tracked separately: **3**.
- Source exception contracts documented with `@throws`/`@Throws`: **241** rows.
- Source deprecation levels found: ERROR=4
- No row is marked `verified` by this inventory generator; the test harness and behavior work own semantic verification.

`api-inventory.tsv` includes the authoritative KLIB source declaration and the JVM ABI entries as separate representations. KLIB records whose source declaration is internal/private are retained in their own implementation-ABI representation. The API dump cannot prove implementation semantics; Kotlin PSI and JVM metadata establish declaration identity, with `unverified` for exact local declarations and `missing` when none exists. `local_contract_differences` preserves parameter/default/visibility differences and `local_implementation_refs` points to source bodies or declared runtime bridges.

## Surface and exclusions

- Common Kotlin APIs remain in scope even though the KLIB dump advertises JS, Wasm, Android Native, Linux, and MinGW targets. A common declaration is not target-out merely because those targets also compile it.
- Entries carrying the upstream `// Targets: [apple]` marker are in-scope Apple APIs.
- Every entry from the JVM ABI dump is kept in scope for Java/JVM interop, including `java.io`, `java.nio`, `Charset`, and ByteString bridges.
- `platform-scope.tsv` records platform-specific source roots and the target-only decision. Native shared actuals remain in scope when they implement a common/native contract.
- Platform source counts include only top-level non-actual declarations in the listed roots; KLIB/JVM API dumps remain authoritative for the exported surface.
- The source API rows come from upstream API dumps; they do not synthesize Okio-only `ByteString.hex()`, `Buffer.snapshot(byteCount)`, or `select` APIs. The generator has explicit guards for these false positives.

## Reproducibility

The checked-in upstream snapshot is verified against both Git blob SHA-1 and SHA-256 from `upstream-lock.json`. The test catalog is pinned by Git blob SHA and file size at the same commit.
The JVM artifacts are fixed by Maven coordinate and SHA-256 in the lock; use `python3 Scripts/io_api_inventory/generate.py --check --verify-jars /path/to/jars` with files named by artifact or `--download-jars` to check them.

```sh
python3 Scripts/io_api_inventory/generate.py --write
python3 Scripts/io_api_inventory/generate.py --check
python3 Scripts/io_api_inventory/generate.py --check --verify-jars /tmp
```

## Owner routing

Rows route to KUU-1729 (Buffer/Segment), KUU-1730 (source/sink lifecycle and common helpers), KUU-1731 (primitive/ByteArray I/O), KUU-1733 (UTF-8), KUU-1760 (ByteString), KUU-1761 (Filesystem), KUU-1762 (JVM interop/ABI/typealiases), or KUU-1763 (Apple). All are children of KUU-1725; missing declarations stay in scope.

## JVM ABI classification

Generated JVM-only entries are classified separately: `48` default/synthetic entries, `35` property/internal accessors, `1` bridge entries, `22` file facades, `1` companion classes, and `6` fields.
Getter/setter rows are marked as ABI accessors only when an upstream Kotlin property with the matching name exists; methods such as `getByteString` remain source callables.
