@testable import CompilerCore
import TestStdlibCache
import Testing

/// KUU-3026: stdlib inline functions whose bodies stay unparsed in the
/// compact index (`lazy`, `run`, `map`, …) must reach consumer compiles
/// through the artifact's `sema.snapshot`. Snapshots written before the
/// deferred descriptors were registered (schema 1) made codegen emit raw
/// `kk_fn_*` calls that failed to link.
@Suite(.serialized)
struct StdlibSnapshotDeferredInlineTests {
    @Test
    func deferredStdlibInlineCallsLinkAndRunThroughTheArtifact() throws {
        TestStdlibCache.shared.prepare()

        try compileAndRunKotlin(
            """
            fun main() {
                println(lazy { 5 }.value)
                println(listOf(1, 2, 3).map { it * 2 })
                println(run { 7 })
            }
            """,
            expectedOutput: "5\n[2, 4, 6]\n7\n",
            moduleName: "StdlibSnapshotDeferredInline",
            allowDefaultStdlibLibrary: true
        )
    }
}
