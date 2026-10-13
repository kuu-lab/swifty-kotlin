#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCoroutineCancellationEdgeCasesTests {


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


    // DEBT-CORO-005 / BUG-041: `job.cancel()` runs synchronously right after
    // `launch { }` returns, with no intervening suspension point. Under
    // CoroutineStart.DEFAULT the child body never starts, so its `finally`
    // block must not run -- only "done" is printed. A launch/cancel scheduling
    // race that let the child start would additionally print "finally".
    // Confirmed against the real kotlinc/JVM reference via
    // `Scripts/diff_cases/coroutine_launch_cancel_before_start_finally.kt`.
}
#endif
