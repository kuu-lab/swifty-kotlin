#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendFileUseEdgeCasesTests {

    // CLEANUP-STUB-107 removed java.io.File's exists/createNewFile/delete
    // synthetic members. This test originally exercised those alongside the
    // File-independent `use {}` scope-function coverage below; the File
    // section (and its 5 trailing expected lines: false/true/true/true/false)
    // was trimmed since exists()/createNewFile()/delete() no longer exist,
    // leaving the still-valid Closeable/`use {}` edge cases (custom Closeable,
    // exception propagation out of `use {}`, nullable receiver) intact.
    @Test
    func testCodegenCompilesFileUseEdgeCases() throws {
        let source = """
        import java.io.Closeable

        class TraceResource(private val name: String) : Closeable {
            override fun close() {
                println("close:$name")
            }
        }

        fun main() {
            val result = TraceResource("ok").use {
                println("use:ok")
                "done"
            }
            println(result)

            try {
                TraceResource("fail").use {
                    println("use:fail")
                    error("boom")
                }
            } catch (e: Throwable) {
                println("caught")
            }

            val nullable: TraceResource? = null
            println(nullable?.use { "nope" })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FileUseEdgeCases",
            expected:
                """
                use:ok
                close:ok
                done
                use:fail
                close:fail
                caught
                null
                """
                + "\n"
        )
    }
}
#endif
