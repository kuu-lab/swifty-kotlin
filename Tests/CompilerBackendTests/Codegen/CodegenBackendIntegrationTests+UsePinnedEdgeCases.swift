@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // Regression for the same beginFinallyGuard/endFinallyGuard gap fixed for
    // scopeUse: usePinned nested inside an outer try/catch must still let the
    // exception propagate to that catch after its own finally (unpin()) runs.
    func testCodegenCompilesUsePinnedEdgeCases() throws {
        let source = """
        import kotlinx.cinterop.ExperimentalForeignApi
        import kotlinx.cinterop.Pinned
        import kotlinx.cinterop.usePinned

        class Box(var value: Int)

        @ExperimentalForeignApi
        fun main() {
            val ok = Box(1)
            val result = ok.usePinned { pinned: Pinned<Box> ->
                println("use:ok")
                pinned.get().value
            }
            println(result)

            val fail = Box(2)
            try {
                fail.usePinned { pinned: Pinned<Box> ->
                    println("use:fail")
                    error("boom")
                }
            } catch (e: Throwable) {
                println("caught:${e.message}")
            }
            println("after")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "UsePinnedEdgeCases",
            expected:
                """
                use:ok
                1
                use:fail
                caught:boom
                after
                """
                + "\n"
        )
    }
}
