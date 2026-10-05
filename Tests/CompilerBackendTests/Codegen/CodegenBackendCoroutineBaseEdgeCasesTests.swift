#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCoroutineBaseEdgeCasesTests {

    @Test(arguments: [true, false])
    func testSchedulerClockUsesLongABI(useArtifact: Bool) throws {
        let source = """
        import kotlinx.coroutines.test.*

        fun main() {
            val scope = TestScope()
            val scheduler = scope.testScheduler
            scheduler.advanceTimeBy(4294967297L)
            println(scheduler.currentTime)
            println(scope.currentTime)
            scope.advanceTimeBy(2L)
            println(scheduler.currentTime)
            println(scope.currentTime)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "TestSchedulerLongABI",
            expected: "4294967297\n4294967297\n4294967299\n4294967299\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test(
        .disabled("user-defined suspend delay/exception paths not yet correct (STDLIB-CORO-001, DEBT-CORO-004)")
    )
    func testCodegenCompilesCoroutineBaseEdgeCases() throws {
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
#endif
