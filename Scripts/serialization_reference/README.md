# serialization 1.10.0 reference

This directory pins serialization 1.10.0 source/ABI evidence and real JVM
references for KUU-1724. Full API compatibility remains unfinished.

KUU-1745 adds the bounded primitive descriptor factory implementation. The
immutable dump inventory remains reproducible with `implementation: unmapped`;
`implementations.json` is a separate overlay linking two JVM/KLIB factory IDs to
bundled source, fixtures, and the source/cache/separate-library O0/O2 test suite.
`verify` checks those IDs and paths without changing the upstream inventory.
The rest of serialization is still incomplete.

`manifest.json` records the immutable upstream commit
`370c4e3780066b82f746cf38e4733cbe62c94f74` (`v1.10.0`), original paths, Git blob
IDs and SHA-256 for 15 API dumps and the Apache 2.0 license. The tag's Gradle
version is `1.10.1-SNAPSHOT`; the reference uses the published **1.10.0** Maven
artifacts, not a build of that snapshot setting.
The scoped Git attributes retain upstream bytes and their final empty lines;
upstream blob/hash checks still require exact copies.

`declarations.json` retains 3,067 JVM/KLIB dump declarations separately, including
owners, original line numbers, raw signatures, ABI IDs, target sets, and simple
ABI classifications. A target annotation applies to its declaration and children;
it does not restrict later siblings. Target-specific alternative declarations
stay distinct. JVM synthetic/default accessors and exported internal packages
remain visible in the inventory. These are **dump records**, not a deduplicated
source API count. Every implementation mapping starts as `unmapped`; classifications
are evidence from the dump, not a substitute for source-level API review.

The manifest also pins the original primitive descriptor implementation, factory
source, and Native platform builtin registry by Git blob and SHA-256. The bounded
factory projects the Native registry's 30 reserved names and serializer display
names directly; it does not construct unimplemented builtin serializers. `verify`
compares the projection with that registry. The internal descriptor follows the
upstream implementation and opts into the bundled interface's subclass marker.

The eight reference modules are core, JSON, CBOR, ProtoBuf/schema, Properties,
json-io, json-okio, and HOCON. External JVM dependencies are Okio 3.9.0,
kotlinx-io core/bytestring 0.6.0, and Typesafe Config 1.4.1, matching the pinned
tag's dependency catalog. Kotlin JVM **2.3.10** and its bundled serialization
compiler plugin are required; the plugin's SHA-256 is pinned. Published Maven
SHA-1 checksums are checked on download, and every artifact's locked SHA-256 and
size are checked again before compilation. Missing or corrupt artifacts fail;
the runner never substitutes KSwiftK declarations or a reduced classpath.

From the repository root, with Python 3.9 or later and JDK 21:

```bash
python3 Scripts/serialization_reference/reference.py verify
python3 -m unittest discover -s Scripts/serialization_reference -p 'test_*.py'
python3 Scripts/serialization_reference/reference.py fetch --cache /tmp/serialization-jars
python3 Scripts/serialization_reference/reference.py run \
  --cache /tmp/serialization-jars --kotlin-home /path/to/kotlinc-2.3.10 \
  --output /tmp/serialization-reference-results

# Actual primitive factory contract, using the same locked published JVM jars:
python3 Scripts/serialization_reference/reference.py run --case primitive-descriptor \
  --cache /tmp/serialization-jars --kotlin-home /path/to/kotlinc-2.3.10 \
  --output /tmp/primitive-descriptor-reference
```

`fetch` requires network access to Maven Central. `verify` and `run` are offline
after the required toolchain/artifacts are present. Rebuild a changed index with
`reference.py index`; upstream hashes must pass before it can be regenerated.

The Kotlin fixture uses a plugin-generated `@Serializable` model and checks its
descriptor, field names and default values. It checks JSON round-trip/defaults/tree
and malformed input, CBOR round-trip/truncation, ProtoBuf round-trip/schema text,
typed and string Properties maps, both I/O modules' round-trip and delayed parse
failure, and HOCON's actual Config and Java duration serializers. Checks run before
each success line; `expected.stdout` is compared exactly. The caller closes the I/O
sources explicitly. This small fixture checks availability and representative
contracts, not all settings, wire layouts, resource ownership, or upstream tests.

The output directory retains compiler/runtime stdout and stderr, the generated
JAR, actual command arguments, toolchain version output, source/plugin hashes and
exit codes in `evidence.json`. JVM execution was verified on Linux with JDK 21 and
Kotlin 2.3.10. For the full eight-module suite, Native/macOS backend and distribution, the upstream full suites,
KSwiftK source/prebuilt/separate-library consumers, and O0/O2 compatibility remain
work for other children of KUU-1724. HOCON's Java dependencies require a real native
implementation or explicit bridge; this JVM reference does not settle that choice.
