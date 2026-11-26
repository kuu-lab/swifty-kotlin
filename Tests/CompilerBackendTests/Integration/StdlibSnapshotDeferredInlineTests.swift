@testable import CompilerCore
import TestStdlibCache
import Testing

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
