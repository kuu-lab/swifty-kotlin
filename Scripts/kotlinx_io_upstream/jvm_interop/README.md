# KUU-1762 retained JVM/Native interoperability closure

The upstream commit is `362bdc35e159bad6da1e08101c8321792d762281`, Kotlin 2.3.10.
The exact JVM reference probe is evidence for official Java descriptors and flags; Native
source, `.kklib` metadata and emitted classfiles have separate states.

`native-api-shapes.expected.json` pins 28 public Java-facing signatures and the
Native exception aliases. Core checks actual source and fresh artifact imports,
selected overloads, named/default mappings, annotations and callback effects.
The 156-line supplement is pinned to actual reference stdout by
`supplement-156-reference-lines.json` and `reference-provenance.json`.

All candidate cases and original IDs remain NOT_RUN. Required future modes are
source O0/O2 and fresh user-producer library → consumer-only O0/O2; the original
suite driver additionally uses stdlib-library O0/O2. The preceding five IO child
proposals are prerequisites; the 1762 patch is an overlay delta and preserves
1729 V3's one existing Buffer.hintEmit marker and computed unsafe contexts.

V6 retains the preceding 137 observed lines and adds lazy stream descriptions,
SequenceInputStream validation/close/error composition. The separate 12-line
FileChannel producer has actual JVM evidence and Native source/library O0/O2
cases. None has been executed on the candidate.

The prepared scoped port of the 235 logical original IDs (599 unique executions
through the original six SourceFactory/two SinkFactory concrete classes) is no
longer committed. Six original driver modes remain HOLD until Root release and independent audit.

V7 extends the existing Sequence test with InputStream.copyTo and markSupported
through the actual Sequence handle. Its three new lines are observed JVM stdout.
Of the 155 retained rows, seventy-nine have an original body mapping; 76 have
only additional Native representation obligations.
No original execution establishes physical Java facades, ACC flags or descriptors;
those remain official reference facts. All planned Native cases remain NOT_RUN.

`native-default-obligations.expected.json` derives all 43 JVM $default rows from
locked official Kotlin metadata and the exact underlying regular descriptor.
The new Core source/fresh-artifact case checks the semantic parameter types,
default flags and a nonempty actual Native default-stub link. It does not assert
that a Native link has a Java descriptor or name, or execute a default wrapper.
Default constructors, facade declarations, singleton fields and other properties
still require their separate shape/behavior evidence before all155 closure.
