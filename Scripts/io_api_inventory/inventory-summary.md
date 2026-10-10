# kotlinx-io 0.9.1 API inventory

Upstream: [`Kotlin/kotlinx-io@362bdc35e159bad6da1e08101c8321792d762281`](https://github.com/Kotlin/kotlinx-io/tree/362bdc35e159bad6da1e08101c8321792d762281) (tag `0.9.1`).
Kotlin compiler baseline: `2.3.10`.

## Generated counts

- Kotlin/KLIB source declaration rows: **280**.
- JVM ABI dump rows: **369**, including **119** generated/accessor rows kept separate from Kotlin source callables.
- KLIB rows backed by non-public implementation declarations: **35**; these are separate from public source APIs.
- `@PublishedApi internal` implementation ABI rows: **18**.
- Rows marked missing because no same-kind, same-name local candidate was found: **27**.
- Rows with a same-kind, same-name local candidate but without semantic verification: **675**.
- Source exception contracts documented with `@throws`/`@Throws`: **280** rows.
- Source deprecation levels found: ERROR=2
- No row is marked `verified` by this inventory generator; the test harness and behavior work own semantic verification.

`api-inventory.tsv` includes the authoritative KLIB source declaration and the JVM ABI entries as separate representations. KLIB records whose source declaration is internal/private are retained in their own implementation-ABI representation. The API dump cannot prove implementation semantics; the conservative local scan reports `unverified` when a candidate declaration exists and `missing` when none is found.

## Surface and exclusions

- Common Kotlin APIs remain in scope even though the KLIB dump advertises JS, Wasm, Android Native, Linux, and MinGW targets. A common declaration is not target-out merely because those targets also compile it.
- Entries carrying the upstream `// Targets: [apple]` marker are in-scope Apple APIs.
- Every entry from the JVM ABI dump is kept in scope for Java/JVM interop, including `java.io`, `java.nio`, `Charset`, and ByteString bridges.
- `platform-scope.tsv` records platform-specific source roots and the target-only decision. Native shared actuals remain in scope when they implement a common/native contract.
- Platform source counts include only top-level non-actual declarations in the listed roots; KLIB/JVM API dumps remain authoritative for the exported surface.
- The source API rows come from upstream API dumps; they do not synthesize Okio-only `ByteString.hex()`, `Buffer.snapshot(byteCount)`, or `select` APIs. The generator has explicit guards for these false positives.

## Reproducibility

The checked-in upstream snapshot is verified against both Git blob SHA-1 and SHA-256 from `upstream-lock.json`. The test catalog is pinned by Git blob SHA and file size at the same commit.
The JVM artifacts are fixed by Maven coordinate and SHA-256 in the lock; use `python3 Scripts/io_api_inventory/generate.py --verify-jars /path/to/jars` with files named by artifact or `--download-jars` to check them.

```sh
python3 Scripts/io_api_inventory/generate.py --write
python3 Scripts/io_api_inventory/generate.py --check
python3 Scripts/io_api_inventory/generate.py --verify-jars /tmp
```

## Owner routing

Rows route to existing KUU-1729 (Buffer/Segment), KUU-1730 (buffered source/sink lifecycle), or KUU-1731 (primitive/ByteArray I/O), KUU-1733 (UTF-8), and KUU-1725 otherwise. ByteString, Filesystem, JVM interop, and Apple-specific families have no dedicated child ticket in the current Linear child list and are therefore left with parent KUU-1725 for triage/splitting; they are not silently marked out of scope.

## JVM ABI classification

Generated JVM-only entries are classified separately: `54` default/synthetic entries, `35` property/internal accessors, `1` bridge entries, `22` file facades, `1` companion classes, and `6` fields.
Getter/setter rows are marked as ABI accessors only when an upstream Kotlin property with the matching name exists; methods such as `getByteString` remain source callables.
