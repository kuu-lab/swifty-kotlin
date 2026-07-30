@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesCoroutineCancellationEdgeCases() throws {
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

        // `cancelJob.cancel()` runs synchronously right after `launch { }` returns, with no
        // intervening suspension point -- matching kotlinx.coroutines' CoroutineStart.DEFAULT
        // semantics, the child body never starts, so "cancelled" is never printed. Confirmed
        // against the real kotlinc/JVM reference via `Scripts/diff_cases/coroutine_cancellation_edge_cases.kt`.
        try assertKotlinOutput(
            source,
            moduleName: "CoroutineCancellationEdgeCases",
            expected:
                """
                null
                boom

                """
        )
    }

    // DEBT-CORO-005 / BUG-041: `job.cancel()` runs synchronously right after
    // `launch { }` returns, with no intervening suspension point. Under
    // CoroutineStart.DEFAULT the child body never starts, so its `finally`
    // block must not run -- only "done" is printed. A launch/cancel scheduling
    // race that let the child start would additionally print "finally".
    // Confirmed against the real kotlinc/JVM reference via
    // `Scripts/diff_cases/coroutine_launch_cancel_before_start_finally.kt`.
    func testCodegenLaunchCancelBeforeStartSkipsFinally() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            val job = launch {
                try {
                    delay(Long.MAX_VALUE)
                } finally {
                    println("finally")
                }
            }
            job.cancel()
            job.join()
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LaunchCancelBeforeStartSkipsFinally",
            expected:
                """
                done

                """
        )
    }
}
