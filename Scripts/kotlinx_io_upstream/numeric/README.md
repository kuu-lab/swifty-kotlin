# Numeric and ByteArray contract preparation (KUU-1731)

This is a prepared validation scope, not a Native verification result. The
pinned API ledger contains 46 common/native rows and 45 core JVM ABI rows;
all 91 remain UNVERIFIED. The baseline is Kotlin 2.3.10 and kotlinx-io 0.9.1,
upstream commit `362bdc35e159bad6da1e08101c8321792d762281`.

`api-shapes.expected.json` derives the 46 common function shapes from the
pinned upstream declaration headers. Six same-file/private/default controls
also cover the private array implementation, byte and ByteString search,
prefix search, ByteString sink writes, and the canonical three-parameter
ByteArray sink write overload. These six controls are not new API ledger rows.
The existing shorter sink-write convenience overloads are retained.

The source restoration adds nine official `@OptIn` declarations in three
Kotlin files; operational bodies and defaults are unchanged. Kotlin 2.3.10
defines OptIn with SOURCE retention. Core tests therefore require the exact
source marker class identities and argument order, while library tests require
the annotation to be absent and the declaration, visibility, receiver,
parameter and default contract to survive. Package-extension defaults require
real emitted default stubs; interface declarations retain their default masks.
The private array helper must fail at consumer call sites in both modes.

`IONumericContractsExecutionTests` preserves seven existing repository diff
fixture bodies, three supplementary boundary fixture bodies, and both original
compound drivers. The additional consumer calls both drivers through fully
qualified names. `entryPointFQName` selects only
`kuu1731integration.driver.main`, so the other fixture mains are ordinary
called functions. Source and current stdlib-library O0/O2 lanes run all ten
fixtures. Two additional lanes compile the twelve producer source files into
real objects and metadata, then compile only the independent consumer against
that artifact. No producer source may enter the consumer compilation.

The three boundary fixtures observe signed and unsigned limits, endianness,
floating signed zero/subnormals/finite limits/infinities/NaN wire bytes and raw
read payloads, buffer and Source/Sink dispatch, segment splits, small upstream
chunks, ByteArray named/default/explicit ranges, invalid bounds, partial EOF
destination state, and all eighteen primitive reader forms at insufficient
byte counts. Their 1459 payload rows (552 numeric + 415 array + 492 EOF)
plus six driver BEGIN/END rows make 1465 raw stdout rows. The original
fixtures have 280 payload plus fourteen driver rows, or 294 raw rows; together
the exact combined reference has 1759 rows. Boundary checks supplement the
original fixture contracts.
They do not execute upstream test IDs.

The pinned JVM oracle outputs are preserved in the fixtures. A separate actual
JVM producer-jar/consumer-jar compilation also matched their exact composition:
1759 rows / 71685 bytes, compile/compile/run exits 0, empty runtime stderr.
This is reference evidence. All prepared Swift and Native cases remain NOT_RUN.

After the compiler prerequisites and a fresh Swift build, run a fresh focused
test build without `--skip-build` or concurrent SwiftPM operations:

```sh
bash Scripts/swift_test.sh --no-parallel --filter 'IONumericAPIContractTests|IONumericContractsExecutionTests'
```

The intended count is Core 2 methods / 4 source-library cases and Backend
2 methods / 6 execution cases, totaling 4 methods / 10 cases / 2 suites.
Use the repository cache/config/security flags, finite compilation and runtime
deadlines, and report the actual Swift Testing counts. Runtime cases have a
30-second limit. Successful UUID-owned generated artifacts are removed only
after exact outputs, actual exits, source/artifact immutability and full hashes
are recorded outside that directory. Failures preserve inputs and artifacts.
`KSWIFTK_IO1731_RECEIPT_DIRECTORY` can select a durable receipt directory.

KUU-1771's inherited-literal and inapplicable-member fallback repair is a
prerequisite and must first pass its own fresh gates. Imported-const flag loss,
nullable mutable-local smartcasts, missing files helpers and platform.posix
declarations are separate compiler or platform families. Do not compensate
with IO-specific or no-op helpers.

The prepared original-ID crosswalk is a separate scratch artifact. Its 388
exact ledger-method references and 130 neighbor candidates identify actual
IDs in the existing 1188-test catalog, but overload-specific relationships
still require body/binding review. None has a Native PASS credited here.
Actual original bodies, constructors, hooks and per-ID results must be kept
when a scoped original execution matrix is later run. Supplementary fixtures
cannot replace those executions or establish the parent's general paired PASS.

KUU-1760 verified ByteString's own 65 common/native declaration contracts and
76 original assertion IDs across six lanes. It did not include the two
`kotlinx.io.Source.readByteString` API rows in this ledger. The original search
fixture covers their positive use; their original partial/too-short and IO
error/buffered/snapshot cases need separate evidence. Those IO extension rows
remain UNVERIFIED. Historical compiler/artifact evidence is not relabelled as
fresh evidence for the current compiler.

The 45 JVM rows here describe core JVM public ABI/Java interoperability.
Native common API behavior does not prove Java descriptors or unsigned JVM
method names. KUU-1762 separately owns ByteString's 60 JVM rows. A scoped Native
result must not mark either JVM group VERIFIED; the issue's JVM scope needs an
explicit evidence or ownership disposition before whole-issue completion.


V2 failure-evidence correction: non-zero CommandRunner results are caught;
stdout/stderr are encoded from the returned Strings without trimming, saved
with argv/exit/hash/size outside the failed UUID, then the original error is
rethrown. Timeout/launch errors expose only formatted diagnostics, so receipts
explicitly leave actual exit and raw original bytes unknown. No generated
failure directory is removed. Successful cleanup remains proof-before-cleanup.
This harness change and all prepared cases have not been Swift typechecked or
executed; parsing alone is not validation of the exception-path behavior.
