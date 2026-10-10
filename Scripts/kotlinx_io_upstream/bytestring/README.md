# ByteString contract verification (KUU-1760)

The baseline is Kotlin 2.3.10 and kotlinx-io 0.9.1, upstream commit
`362bdc35e159bad6da1e08101c8321792d762281`. The API inventory in PR #8300
assigns 65 common/native rows to this issue; the 60 JVM ABI rows belong to
KUU-1762. The common/native `UnsafeByteStringApi` annotation class is included
even though the original inventory partition classified that row separately.

`api-shapes.expected.json` derives signatures, argument names, defaults,
varargs, visibility, annotations and callback contracts from the pinned
upstream source. Four property/getter pairs and one PublishedApi source/KLIB
pair describe the same declaration, giving 60 distinct semantic declarations.
`ByteStringAPIShapeTests` checks every row against bundled source and imported
metadata. Its library case requires a real cached artifact, imported symbols,
default stubs and getter links; source fallback cannot satisfy that case.
The signed and unsigned varargs use scalar element types with a separate
vararg flag in the compiler's semantic model. Inherited comparison operator
syntax is checked through execution, separately from declared modifier flags.

`api-coverage.tsv` links every row to concrete upstream execution IDs and
supplementary checks. An indirect internal-helper test remains labelled as
indirect coverage. A row's state describes the listed checks, rather than
every possible input. Prepared mappings and failed or unexecuted lanes remain
UNVERIFIED until their required execution and API checks pass.

The 2026-10-10 final audit verified all 65 rows for these listed checks, with
56 direct and 9 indirect/container relationships retained. `validation.json`
records the compiler/artifact identity, gate counts and evidence hashes.
The fresh API/startup/label gate passed 6 methods / 9 cases / 4 suites. All six
original-test lanes passed the same 76 IDs (456 assertion executions), and the
74-line JVM supplement/ABI reference matched Native source/library O2 exactly.
The 7-method / 14-case negative Sema gate is retained from the previous
compiler: all 216 Sema files and relevant helpers are unchanged, and all 1756
old/new stdlib artifact files are byte-identical. It is not a fresh rerun.

The six original common suites contain 76 execution IDs. Their bodies and
constructors remain unchanged; the candidate port only prepends the existing
internal-access suppression. Each ID uses a fresh original class instance.
The five `Scripts/diff_cases/kotlinx_io_bytestring_*contracts.kt`,
`*_decode_destination.kt`, `*_implicit_literals.kt` and `*_api_supplements.kt`
fixtures cover additional named/default arguments, literal narrowing, typed
exception priorities, Base64 partial writes/padding, Hex formatting/parsing,
backing identity, callback count/throw/non-local return, opt-in and comparison
syntax. Their `.expected` files are outputs from the pinned JVM reference.
The corresponding Core and Backend tests also check import scope and source
versus library behavior.

After `swift build`, run the focused tests with a fresh test build:

```sh
bash Scripts/swift_test.sh --no-parallel --filter 'ByteStringAPIShapeTests|ByteStringBuilderContractTests|ImplicitReceiverLiteralExtensionTests|scalarUnsignedAndSignedArraysRemainStable|testByteStringImplicitBuilderLiteralContracts|testByteStringConstructorUnsafeAndAppendableContracts|testByteStringBuilderDefaultsExtensionsAndUnsafeContract|testByteStringCodecBoundsPaddingAndHexContracts|testByteStringDecodeDestinationAndHexLengthContracts|constructorReflectionPreservesPackedVarargArrays|channelCloseCallbacksPreserveCallableClosureABI|TopLevelStartupIsolationTests|TopLevelInitializerLabelKIRTests|callingOtherMainAndReenteringEntryPreservesModuleState'
```

The combined driver is provided by the parent harness PR #8301. For each O0/O2
lane, run the following with the pinned checkout and compiler-built stdlib:

```sh
python3 Scripts/kotlinx_io_upstream/run_candidate_suites.py \
  --upstream /path/to/kotlinx-io-0.9.1 --compiler .build/debug/kswiftc \
  --package-root . --stdlib-library /path/to/stdlib.kklib \
  --optimization O0 --output /path/to/new-results-directory \
  --compile-timeout 300 --run-timeout 30 \
  --suite kotlinx.io.bytestring.ByteStringBase64Test \
  --suite kotlinx.io.bytestring.ByteStringBuilderTest \
  --suite kotlinx.io.bytestring.ByteStringHexTest \
  --suite kotlinx.io.bytestring.ByteStringTest \
  --suite kotlinx.io.bytestring.samples.ByteStringSamples \
  --suite kotlinx.io.bytestring.unsafe.UnsafeByteStringOperationsTest
```

Replace `--stdlib-library ...` with `--stdlib-from-source` for the source lane.
Add `--test-library` to the library lane to compile original test bodies into
a separate `.kklib`, then compile only the driver as its consumer. These are
six lanes in total. Keep the commands, input/artifact hashes, streams, exit
codes and per-ID results. Every lane must finish all 76 assertions; compile
failure, missing IDs, failed cleanup or timeout cannot count as PASS.

This is ByteString assertion and contract coverage. The parent harness's
general seven-observation comparison and full core/JVM/Apple coverage remain
owned by KUU-1727/KUU-1725. General paired PASS is not inferred from these
assertion results. HexFormat builder setter validation is tracked separately
in KUU-1767.

Startup initialization belongs only to the selected executable file-level
entry and runs once, including recursive entry calls. Other package `main`
functions and library functions preserve singleton state. Core selection and
label checks plus source/library execution cover this regression. Argument
passing to `main(args)` remains a separate KUU-1770 entry ABI issue.
