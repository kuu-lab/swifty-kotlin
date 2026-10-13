# atomicfu Kotlin/Native reference (KUU-1735)

This is a real upstream oracle, separate from KSwiftK candidate execution.
The lock fixes atomicfu **0.33.0**, source commit
`fc175fc575419ca9eae0d3c14cefe9c5cd7ca351`, and Kotlin/Native **2.3.10**.
It currently covers a **Linux/x86_64 host and linux_x64 target**. Other hosts
are reported as `UNSUPPORTED`, never as a Native pass.

`lock.json` records URLs, byte sizes and SHA-256 for the official Kotlin
release, its LLVM 19/GCC sysroot/libffi/LLDB dependencies, the Maven Central
Native and cinterop KLIBs, their source JAR, and the JVM contrast JAR. The
KLIB manifests record compiler **2.2.21**, ABI **2.2.0** and `linux_x64`.
The 2.3.10 consumer actually compiles, links and runs these artifacts; this
compatibility is not inferred from a declaration or a version string alone.

## Run

Use Python 3.9+, JDK 21 and `tar`. Allow roughly 600 MB for downloads and
2 GB for an extracted run. The cache and outputs should be outside Git.

```bash
python3 Scripts/atomicfu_native_reference/reference.py check
python3 Scripts/atomicfu_native_reference/reference.py fetch --cache /tmp/atomicfu-native-cache
python3 Scripts/atomicfu_native_reference/reference.py run \
  --cache /tmp/atomicfu-native-cache --output /tmp/atomicfu-native-run \
  --jvm-kotlinc /path/to/kotlinc-2.3.10/bin/kotlinc
python3 -m unittest discover -s Scripts/atomicfu_native_reference -p 'test_*.py'
```

The optional `--jvm-kotlinc` executes the JVM contrast with Kotlin 2.3.10.
Its host compiler distribution is supplied by the caller; the atomicfu JAR
is checksum-locked. Omitting it records `jvm_status: NOT_REQUESTED`.

`fetch` honors the standard Python proxy environment and validates both
cached and downloaded files. A corrupt cache is an error; delete that one
file deliberately before fetching again. A run re-verifies every required artifact
(the JVM JAR is required only when `--jvm-kotlinc` is supplied),
extracts the locked archives into a new/empty output directory, and enables
Kotlin/Native `airplaneMode=true`. Native compilation cannot silently fetch
unlocked dependencies. Existing `JAVA_OPTS` are preserved. The selected PATH
Java is resolved, validated as JDK 21 and supplied through per-process
`JAVACMD`/`JAVA_HOME` to both compilers, so an unrelated inherited JAVA_HOME
cannot change the recorded JDK. Timeout stops the entire compiler process
group, including Java/LLVM descendants, before finalizing logs.

`report.json` records action, status, source and artifact hashes, KLIB
manifests, compiler/JDK versions, and compile/run commands and exit codes.
Separate stdout/stderr logs retain compiler warnings and actual program
output. `check` validates the checked-in fixture hashes; `fetch` validates
distribution bytes. Their `PASS` does **not** mean Native code executed:
`native_status` remains `NOT_RUN`. Only `run` can set it to `PASS`.

## Platform expectations

The two source fixtures and separate expected outputs encode these observed
differences. They intentionally do not attempt to compile Native-only APIs
on JVM.

| Probe | Native | JVM contrast |
| --- | --- | --- |
| Real scalar CAS + getAndAdd | true, prior value 8, final 10 | same |
| Trace and named Trace identity | both `TraceBase.None` | neither `TraceBase.None` |
| Trace event lambda / formatter | event executes once, formatter never runs | same counts in this probe |
| ReentrantLock | `SynchronizedObject()` is assignable to Native alias | `reentrantLock()` factory |
| Nested withLock + tryLock | 7 + true | same |
| Unlock without ownership | `IllegalArgumentException` | `IllegalMonitorStateException` |
| Negative AtomicIntArray size | `IllegalArgumentException` | `NegativeArraySizeException` |
| ParkingSupport | thread handle identity, pre-unpark + infinite park, timed park return | Native-only; omitted |

The parking run has a 15-second timeout. It verifies a pre-issued permit and
a finite park return on one thread; it does not establish cross-thread
wakeup, scheduling fairness, or timing precision. The Native scalar uses
the real linked atomicfu implementation, not a fake CAS. The Trace no-op is
an explicit Native contract checked by identity and event/formatter counts.
Both programs must exit zero, match their own stdout exactly, and emit no
runtime stderr. The deprecated AtomicIntArray constructor can produce a
compile warning, retained in the compile log.

## Outcomes and limits

| Status | Exit | Meaning |
| --- | --- | --- |
| PASS | 0 | Requested action succeeded; inspect native_status/jvm_status |
| DIFFERENCE | 1 | Runtime stdout/stderr differs from that platform's oracle |
| ERROR | 2 | Hash, extraction, manifest, compilation or execution failure |
| UNSUPPORTED | 77 | Unsupported host, missing offline artifacts or unavailable required toolchain |
| TIMEOUT | 124 | Compile or program exceeded its configured deadline |

Failed runs keep `report.json` and available logs. Deadlines are configurable
with `--compile-timeout` (default 300 seconds) and `--run-timeout` (default 15).
This reference does not compare KSwiftK, run upstream's full suite, cover
Apple/other Native targets, or establish concurrent atomic semantics.
The API inventory dependency KUU-1732 remains tracked separately; this
environment does not import or claim completion of that implementation.
