#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// End-to-end scheduling behaviour of `runBlocking`.
///
/// The expectations below are the real kotlinc/JVM reference output, pinned by
/// `Scripts/diff_cases/coroutine_yield_fifo_order.kt` and
/// `Scripts/diff_cases/coroutine_start_modes.kt`. They each end with a blank
/// line because `assertKotlinOutput` compares raw stdout, which keeps the final
/// `println`'s newline.
@Suite
struct CodegenBackendCoroutineSchedulingTests {

    /// `yield()` re-dispatches to the tail of runBlocking's queue, so the
    /// interleaving is FIFO and identical on every run. Before the fix there
    /// was no ready queue: resumptions went to the concurrent global dispatch
    /// pool and their order was decided by thread races, so this program
    /// printed `A2 B2` and `B2 A2` on different runs of the same binary.
    @Test func testCodegenYieldResumesInFIFOOrder() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            launch { println("A1"); yield(); println("A2") }
            launch { println("B1"); yield(); println("B2") }
            println("M"); yield(); println("M2"); yield(); println("M3")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CoroutineYieldFIFOOrder",
            expected:
                """
                M
                A1
                B1
                M2
                A2
                B2
                M3

                """
        )
    }

    /// `CoroutineStart.UNDISPATCHED` runs the body inline on the calling thread
    /// until its first suspension, so `undispatched1` precedes `after launch`.
    /// Every start mode used to reach the lazy launcher, which printed
    /// `after launch` first and only ran the body at `join()`.
    @Test func testCodegenUndispatchedStartRunsBodyInline() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            val job = launch(start = CoroutineStart.UNDISPATCHED) {
                println("undispatched1")
                yield()
                println("undispatched2")
            }
            println("after launch")
            job.join()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CoroutineStartUndispatched",
            expected:
                """
                undispatched1
                after launch
                undispatched2

                """
        )
    }

    /// `CoroutineStart.DEFAULT` schedules the body immediately: a single
    /// `yield()` is enough to run it, with no `join()`. Under the old
    /// lazy-for-everything lowering the body had not started at that point.
    @Test func testCodegenDefaultStartRunsWithoutJoin() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            val job = launch(start = CoroutineStart.DEFAULT) { println("default body") }
            println("after launch")
            yield()
            println("completed without join: ${job.isCompleted}")
            job.join()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CoroutineStartDefault",
            expected:
                """
                after launch
                default body
                completed without join: true

                """
        )
    }
}
#endif
