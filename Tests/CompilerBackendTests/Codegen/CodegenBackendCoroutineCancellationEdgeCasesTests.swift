#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCoroutineCancellationEdgeCasesTests {

    @Test func testTimeoutOrNullUnitResultPreservesNullThroughBoxing() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlin.time.Duration.Companion.milliseconds

        fun main() = runBlocking {
            println(withTimeoutOrNull(1) { delay(5000) })
            println(withTimeoutOrNull(1L) { delay(5000) })
            println(withTimeoutOrNull(1.milliseconds) { delay(5000) })
            println(withTimeoutOrNull(0) { Unit })
            println(withTimeoutOrNull(-1L) { Unit })
            val expired = withTimeoutOrNull(1) { delay(5000) }
            println(expired == null)
            val erased: Any? = expired
            println(erased)
            println("result=$expired")
            val block: suspend CoroutineScope.() -> Unit = { delay(5000) }
            println(withTimeoutOrNull(1L, block))
            println(withTimeoutOrNull(5000) { Unit })
            println(withTimeoutOrNull(5000L) { delay(1) })
            println(withTimeoutOrNull(5000.milliseconds) { Unit })
            println(withTimeoutOrNull(1) { delay(5000); "late" })
            try {
                withTimeout(1) { delay(5000) }
            } catch (e: TimeoutCancellationException) {
                println("timeout")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TimeoutOrNullUnitBoxing",
            expected: """
            null
            null
            null
            null
            null
            true
            null
            result=null
            null
            kotlin.Unit
            kotlin.Unit
            kotlin.Unit
            null
            timeout

            """
        )
    }

    // Duration construction in source-injection mode is tracked separately as KUU-1341.
    @Test func testTimeoutOrNullUnitResultPreservesNullFromStdlibSource() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            println(withTimeoutOrNull(1) { delay(5000) })
            val expired = withTimeoutOrNull(1L) { delay(5000) }
            println(expired == null)
            val erased: Any? = expired
            println(erased)
            println("result=$expired")
            println(withTimeoutOrNull(5000) { delay(1) })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TimeoutOrNullUnitBoxingSource",
            expected: """
            null
            true
            null
            result=null
            kotlin.Unit

            """,
            allowDefaultStdlibLibrary: false
        )
    }

    @Test func testCodegenCompilesCoroutineCancellationEdgeCases() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            val timeoutResult = withTimeoutOrNull(1L) {
                delay(1000)
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
    @Test func testCodegenLaunchCancelBeforeStartSkipsFinally() throws {
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
#endif
