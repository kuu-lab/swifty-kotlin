@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesCoroutineBaseEdgeCases() throws {
        throw XCTSkip("user-defined suspend delay/exception paths not yet correct (STDLIB-CORO-001, DEBT-CORO-004)")
        let source = """
        import kotlinx.coroutines.*

        suspend fun step(value: Int): Int {
            delay(1)
            return value + 1
        }

        suspend fun failStep(): Int {
            delay(1)
            throw IllegalStateException("suspend-boom")
        }

        fun main() = runBlocking {
            val ok = step(41)
            println(ok)

            try {
                failStep()
            } catch (e: IllegalStateException) {
                println(e.message)
            }

            val resumed = withContext(Dispatchers.Default) {
                step(9)
            }
            println(resumed)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CoroutineBaseEdgeCases",
            expected:
                """
                42
                suspend-boom
                10
                """
        )
    }
}

