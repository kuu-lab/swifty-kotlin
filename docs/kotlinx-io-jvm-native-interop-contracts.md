# Current prepared Native interoperability scope (V9)

All candidate compilation, typecheck and Native cases are NOT_RUN. Current
focused scope: Core11 methods/27 cases, Runtime9 methods/10 cases, Backend2
methods/8 cases: **22 methods/45 cases**. Backend reference observations are
156 + 12 rows in each source/library O0/O2 route (672 planned observations).
The complete ledger retains155 rows (101own/54cross) and235 logical original
IDs expanding to599 concrete Source/Sink factory executions; all are NOT_RUN.
Physical JVM facade/descriptor/ACC-field representation is official-reference
only and is not emitted or claimed by the Native backend.

The preceding preparation history below records earlier stages. V5/V6/V7 case
counts and their gates are historical snapshots, not the current scope.

# kotlinx-io 0.9.1 JVM interoperability through Native source and libraries

KUU-1762 follows the parent KUU-1725 Native compatibility contract. It retains
all 155 inventory rows (101 assigned to 1762 and 54 representation obligations
owned by other children) and all 235 concrete original test IDs. The pinned
upstream is `362bdc35e159bad6da1e08101c8321792d762281`; Kotlin is 2.3.10.

The implementation preserves the 28 public Java-facing Kotlin declarations:
InputStream/OutputStream adapters, Buffer stream transfer/ranged copy, NIO
Buffer/Source/Sink/channel extensions, Charset read/write and ByteString
conversion, and the unsafe ByteBuffer head/tail/iovec overloads. The original
Kotlin algorithms, defaults, parameter names, visibility, annotations and
EXACTLY_ONCE contracts are kept. Source/Sink stream creation owns callbacks
rather than consuming input eagerly. Range callbacks receive the original
ByteArray and arguments so source closed checks, bulk short reads, failed-write
nonconsumption, and original throwable identity survive the Native boundary.

Native ByteBuffer supplies the views, positions, limits, marks, read-only checks,
bulk overlap snapshots and bean property syntax required by these declarations.
A direct buffer records direct intent with shared Native heap storage; it does
not expose an off-heap Java address or the complete JDK ByteBuffer class surface.
The in-memory Java stream producers retain input array sharing, mark/reset and
close no-ops, and isolate output snapshots. Their typed-erased Closeable dispatch
and nominal parent registrations are exercised separately from source types.

Charset values are source objects in `java.nio.charset`, with the Kotlin alias
preserved. Only the private codec boundary accepts an Int tag. Source-backed
Charsets getters therefore remain object getters, and String/ByteArray wrappers
extract the tag before calling existing codecs. The nine built-in codecs cover
UTF-8, ISO-8859-1, US-ASCII, UTF-16/BE/LE and UTF-32/BE/LE, including the names used
by the original suites. This proposal does not claim a complete Java Charset
provider registry, arbitrary custom Charset subclasses, or the complete Java
Reader/Writer API. The existing bufferedReader helper still eagerly decodes
remaining data and does not supply full JDK lazy read/close/error behavior.
The Charset writer can now wrap memory and Source/Sink callbacks and propagate
write/flush/close failures; incremental encoders split across surrogate writes
and repeated BOM-bearing flushes are not covered by this proposal's controls.
Those helper limitations are retained explicitly rather than counted as
verified Java behavior.

The source and actual `.kklib` metadata retain JvmName, JvmField, JvmSynthetic,
unsafe annotations, defaults and native getter/default-stub links. Common
optional JvmName/JvmSynthetic definitions come from the preceding 1729 change;
1762 adds the official common optional JvmField definition. Java IOException,
EOFException and FileNotFoundException resolve to the existing Native common
nominal classes so Kotlin catches and foreign errors retain one identity. The
official JVM alias representation remains a separate inventory fact.

Physical Java file facades, descriptors, fields, ACC_SYNTHETIC, JVM `$default`
entry points and unsigned mangled bridge names are pinned against official JVM
jars by the 155-row reference probe. Native code and `.kklib` getter/default
links do not establish that those classfiles were emitted. The existing
compiler has a Native executable backend, `.kklib` import, and separate Kotlin
`.klib` IR import; no Java classfile/Jar importer or JVM bytecode emitter was
found. No row is removed or relabeled out of scope on that account. These facts
remain reference-observed and physical-emission-unverified in the ledger.
Fresh source/library producers are required; compatibility with old producers
that embedded the former raw-Int Charsets shortcut has not been validated.

## Private bridge budget and ABI

Fourteen private entry points are added under §13-2. The reason is foreign
memory representation, callback environment ownership, and throwable channels:

| Entry points | Count | Boundary |
| --- | ---: | --- |
| `__kk_kotlin_source_input_stream` / `__kk_kotlin_sink_output_stream_range` | 2 | Foreign handle with 4/3 Kotlin callback function/environment pairs |
| `__kk_input_stream_read_range` / `__kk_output_stream_write_range` | 2 | Preserve original array identity and arguments across a foreign stream |
| Input available/close, Output close, BufferedWriter close with `_throwing` | 4 | Keep Kotlin callback throwable handles in outThrown |
| ByteArrayOutputStream new/default/snapshot/reset/size/toString | 6 | Foreign in-memory stream storage used by unchanged original stream bodies |

All are registered in RuntimeABISpec. Its derived specVersion changes with the
specification, and fresh bundled resource/stdlib manifests are mandatory. Old
entry point signatures are unchanged. The existing native string codecs retain
their List versus flat ByteArray storage conventions. Public adapter loops,
validation order and unsafe commit/rollback algorithms remain Kotlin source.
The declaration-token call lowerer expands the new source factory closures to
8/6 words, and the explicit outThrown functions use the same thrown-channel and
rethrow routing as existing foreign calls. Core checks this real KIR boundary;
Runtime tests preserve callback identity, nominal close dispatch and stored
array ownership.

## Prepared verification, not an executed candidate result

`Scripts/kotlinx_io_upstream/jvm_interop` contains the 155-row owner ledger,
28 exact native signatures, 235 original IDs, observed JVM evidence pins and a
153-line supplemental oracle. Every supplemental expected line is an actual
line in a retained JVM stdout. The old missing-InternalIoApi compile failure is
kept alongside the corrected new-input observation. Existing oracle inputs and
failed proofs are never rewritten or blindly retried.

The focused proposal has 8 Core methods/21 parameter cases, 5 Runtime methods/5
cases, and 1 Backend method/4 cases: 14 methods/30 cases in 3 suites. The Backend
runs the 153 lines through source O0/O2 and an actual user producer library plus
consumer-only O0/O2 (548 expected observations). It pins all fixture bytes,
explicit compiler options, full producer/stdlib file sets and hashes, exact
stdout and empty stderr. Success evidence is written outside the temporary
compilation directory before cleanup; failures preserve inputs and executable.
CommandRunner's captured output is UTF-8 decoded and can be partial when draining
fails. The retained outer bounded runner must own raw output, compiler/test
binary/resource/Runtime object provenance, freeze checks and child reap proof.

The original 235 IDs still require an ID-preserving driver with unchanged test
bodies, constructors and helpers, including the owning common-child factories
and platform support. Supplements do not replace them. Fresh build/typecheck,
focused candidate tests, the original lanes, macOS target validation and any
physical JVM ABI emission are all pending. No whole-ticket completion or Native
PASS is recorded by scratch preparation.

V6 additionally supplies the original NioTest regular-file producers through
POSIX-backed FileChannel/Path/Paths/createFile/inputStream, without replacing
those tests with Buffer. Sequential channel read/write preserve ByteBuffer
position and the observed closed/mode/read-only validation order. Java NIO Buffer
base casts and Arrays.fill remain source operations. Mapping/locking/positional
FileChannel and complete Path/FileSystemException surfaces are not claimed.

Source/Sink descriptions are lazy Function0 callbacks. Their adapters return one
boxed/erased String word, preserving the flat String ABI only inside ordinary
source calls. Typed InputStream/OutputStream toString uses a private thrown slot.
The existing Any override registry is reused. A new private object interpolation
entry carries the original overridden toString exception, including the original
RealSource/RealSink descriptions; primitive numeric/null tag paths and the old
public no-thrown-slot Any entry remain unchanged. Erased legacy Any.toString and
collection/console renderer exception policy is a pre-existing limitation and is
not asserted as fixed by these controls.

SequenceInputStream now retains generic stream handles and child references,
including callback and nested Sequence handles, instead of requiring a memory
InputStream box. Range arguments are checked before delegation, zero-length reads
and closed behavior follow the observed JVM controls, and close attempts both
sources even if the first throws. New throwing available/close entries preserve
old single-word exports for legacy callers.

The §13 bridge admission reason for the 21 total private entries is native
foreign storage and error channels: prior 14 entries, three sequential POSIX file
producer entries, typed description and two Sequence error entries, and one
object conversion error entry. Kotlin keeps adapter algorithms and public API
validation. No old public C entry signature is changed. The two unexecuted private
V5 prototype factory signatures grow description Fn/env pairs; fresh stdlib and
user libraries are mandatory and no compatibility with that scratch prototype
is claimed. Native declaration tokens, real callable word counts, ABI spec and
throw-channel Core checks must pass before rollout.

Future focused gate is Core10 methods/25 cases, Runtime8 methods/8 cases,
Backend2 methods/8 cases: 20 methods and 41 cases in three suites. The Backend
observes 153 + 12 exact JVM-derived lines in each source/library O0/O2 route,
660 planned observations. Failure UUIDs and all inputs/artifacts/executables move
to the requested evidence root after LIFO input/library checks, with full maps
before/after and both actual paths; a failed move preserves the old UUID and
reports the error. Captured CommandRunner output is UTF-8-decoded and can be
partial after a failed drain. Retained outer runners still own raw-byte/time/reap
proofs. This preparation does not count any future case or original ID as PASS.

V7 closes two general InputStream dispatch guards for SequenceInputStream:
markSupported returns false, while copyTo uses the already implemented polymorphic
range reader and preserves copied prefixes and the original IOException. No ABI
entry/signature changes. The existing Runtime sequence scenario and Native
source/library O0/O2 supplement now include the three actual JVM controls.
The supplement is 156 rows, plus the separate 12-row FileChannel producer (672
future observations). Method/case totals stay 20/41. Every candidate case remains
NOT_RUN. The exact row→599 original-execution mapping explicitly identifies 79
rows with original bodies and 76 requiring additional Native metadata/default/
getter/annotation counterpart evidence. It cannot establish emitted JVM facades.

The additional V7 Core source/artifact method verifies all 43 default-function
counterparts from exact official metadata. Focused counts are now Core11/27,
Runtime8/8, Backend2/8: 21 methods and 43 cases. Wrapper runtime observations are
separate: a metadata link alone is not an executed default call. Five default
constructor rows, file facades, singleton fields and published/getter rows retain
separate obligations. The original ledger owner and all235 IDs are unchanged.

V8 closes the Native byte-array producer representation gap. InputStream
readAllBytes/readBytes now allocates a fresh ArrayBox and registers the known
primitive kotlin.ByteArray nominal type at that allocation boundary. This does
not sample element values, retag an erased reference Array, change reference
components, or alter a C entry signature. The additional Runtime method has
empty/nonempty cases, each exercising real memory/callback/Sequence readAllBytes
allocation followed by the actual nominal check and typed callBy bridge. It
checks bytes, whole-array identity, invocation count and zero default mask.
The new distinct Kotlin source reference for this typed composition is prepared
but has NOT_RUN during Root's Main gate; it is not included in observed JVM lines
or in Backend reference156 until a bounded one-shot JVM result is retained.

V9 keeps the same two Runtime cases and adds the incompatible List control before
the real typed callBy succeeds. Both cases assert the actual nominal rejection,
IllegalArgumentException and zero invoker count before checking that the produced
ByteArray reaches the bridge with unchanged whole-array identity and a zero mask.
Production source bytes and all public/private C signatures remain V8-identical.
