#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Testing

@Suite
struct CodegenBackendSuspendReceiverFunctionValueTests {
    @Test
    func testInterfaceDefaultMethodAssignsThroughCapturedReceiverFromSuspendLambda() throws {
        let source = """
        import kotlin.coroutines.*

        private val completion = object : Continuation<Unit> {
            override val context: CoroutineContext = EmptyCoroutineContext
            override fun resumeWith(result: Result<Unit>) {}
        }

        fun builder(block: suspend String.() -> Unit) {
            block.startCoroutine("OK", completion)
        }

        fun <T> builder(receiver: T, block: suspend T.() -> Unit) {
            block.startCoroutine(receiver, completion)
        }

        interface Holder {
            var result: String
            fun test(): String {
                builder { result = this }
                return result
            }
        }

        interface GenericHolder<T> {
            var result: T
            fun test(receiver: T): T {
                builder(receiver) { result = this }
                return result
            }
        }

        fun main() {
            println(object : Holder { override var result = "Fail" }.test())
            println(object : GenericHolder<String> { override var result = "Fail" }.test("OK"))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "InterfaceDefaultSuspendReceiverAssignment",
            expected: "OK\nOK\n",
            allowDefaultStdlibLibrary: true
        )
    }

    @Test(arguments: [true, false])
    func testRunTestAcceptsSuspendExtensionReferences(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        import kotlinx.coroutines.test.*

        @OptIn(ExperimentalCoroutinesApi::class)
        suspend fun TestScope.fnBody() {
            println("fnref t0=$currentTime")
            advanceTimeBy(9)
            println("fnref t1=$currentTime")
        }

        @OptIn(ExperimentalCoroutinesApi::class)
        fun main() {
            runTest(testBody = TestScope::fnBody)
            val typed: suspend TestScope.() -> Unit = TestScope::fnBody
            runTest(testBody = typed)
            val inferred = TestScope::fnBody
            runTest(testBody = inferred)
            println("done")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "RunTestSuspendExtensionReferences",
            expected: "fnref t0=0\nfnref t1=9\nfnref t0=0\nfnref t1=9\nfnref t0=0\nfnref t1=9\ndone\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test
    func testDeepRecursiveTrampolineKeepsStoredCapturedEntry() throws {
        let source = """
        fun main() {
            val step = 3
            val body: suspend DeepRecursiveScope<Int, Int>.(Int) -> Int = { n ->
                if (n <= 0) 0 else callRecursive(n - step) + 1
            }
            val countDown = DeepRecursiveFunction<Int, Int>(body)
            println(countDown(9))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "DeepRecursiveStoredCapturedEntry",
            expected: "3\n"
        )
    }

    @Test
    func testStoredReceiverValueRetainsCapturesThroughSuspendParameter() throws {
        let source = """
        import kotlinx.coroutines.*

        suspend fun invokeBody(receiver: String, body: suspend String.() -> Unit) {
            body(receiver)
        }

        suspend fun invokeValue(receiver: Int, body: suspend Int.(Int) -> String): String {
            return body(receiver, 3)
        }

        fun main() {
            val label = "v"
            val body: suspend String.() -> Unit = {
                println("$label:$this")
                delay(1)
                println("$label:$this")
            }
            val number = 7
            val value: suspend Int.(Int) -> String = { extra ->
                delay(1)
                "$label:$number:${this + extra}"
            }
            runBlocking {
                body("direct")
                invokeBody("forwarded", body)
                println(invokeValue(10, value))
            }
            println("done")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "SuspendReceiverFunctionValue",
            expected: "v:direct\nv:direct\nv:forwarded\nv:forwarded\nv:7:13\ndone\n"
        )
    }

    @Test
    func testRunTestPreservesStoredForwardedAndLiteralCaptures() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.test.*

        @OptIn(ExperimentalCoroutinesApi::class)
        fun execute(body: suspend TestScope.() -> Unit) {
            runTest(testBody = body)
        }

        @OptIn(ExperimentalCoroutinesApi::class)
        fun main() {
            val label = "v"
            val number = 7
            val body: suspend TestScope.() -> Unit = {
                println("$label:$number:$currentTime")
                advanceTimeBy(3)
                println("$label:$number:$currentTime")
            }
            runTest(testBody = body)
            execute(body)
            runTest { println("$label:$currentTime") }
            println("done")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "RunTestSuspendReceiverCaptures",
            expected: "v:7:0\nv:7:3\nv:7:0\nv:7:3\nv:0\ndone\n"
        )
    }
}
#endif
