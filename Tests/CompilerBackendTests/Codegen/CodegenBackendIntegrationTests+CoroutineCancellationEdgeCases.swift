@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesCoroutineCancellationEdgeCases() throws {
        throw XCTSkip("withTimeoutOrNull null semantics and coroutineScope exception propagation not yet correct (STDLIB-CORO-001, DEBT-CORO-003)")
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            val timeoutResult = withTimeoutOrNull(1L) {
                delay(10)
                1
            }
            println(timeoutResult)

            val cancelJob = launch {
                try {
                    delay(100)
                    println("unexpected-complete")
                } catch (e: CancellationException) {
                    println("cancelled")
                }
            }
            cancelJob.cancel()
            cancelJob.join()

            try {
                coroutineScope {
                    throw IllegalStateException("boom")
                }
            } catch (e: IllegalStateException) {
                println(e.message)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CoroutineCancellationEdgeCases",
            expected:
                """
                null
                cancelled
                boom
                """
        )
    }
}

