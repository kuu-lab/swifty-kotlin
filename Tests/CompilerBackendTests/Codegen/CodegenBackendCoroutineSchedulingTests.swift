#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCoroutineSchedulingTests {


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

    @Test func testAsyncWaitsForNestedChildrenBeforeCompletion() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            async {
                println("outer async first")
                launch {
                    println("nested launch first")
                    yield()
                    println("nested launch second")
                }
                async {
                    println("nested async first")
                    yield()
                    println("nested async second")
                }
                yield()
                println("outer async second")
            }
            launch {
                println("sibling launch first")
                yield()
                println("sibling launch second")
            }
            yield()
            println("nested parent")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "AsyncWaitsForNestedChildren",
            expected:
                """
                outer async first
                sibling launch first
                nested parent
                nested launch first
                nested async first
                outer async second
                sibling launch second
                nested launch second
                nested async second

                """
        )
    }

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
