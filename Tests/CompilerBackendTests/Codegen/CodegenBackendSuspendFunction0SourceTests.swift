#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CodegenBackendSuspendFunction0SourceTests {
    @Test(arguments: [true, false])
    func testInterceptedSourceBodyPreservesIdentity(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.CoroutineContext
        import kotlin.coroutines.EmptyCoroutineContext
        import kotlin.coroutines.resume
        import kotlin.coroutines.intrinsics.createCoroutineUnintercepted
        import kotlin.coroutines.intrinsics.intercepted

        class Probe : Continuation<String> {
            override val context: CoroutineContext
                get() = throw IllegalStateException("context must not be read")
            override fun resumeWith(result: Result<String>) {
                println(result.getOrThrow())
            }
        }

        suspend fun value(): Int = 42

        fun main() {
            val source: Continuation<String> = Probe()
            println(source.intercepted() === source)
            source.intercepted().resume("ok")
            val completion = Continuation<Int>(EmptyCoroutineContext) { result ->
                println(result.getOrThrow())
            }
            println(completion.intercepted() === completion)
            val pending = (::value).createCoroutineUnintercepted(completion)
            println(pending.intercepted() === pending)
            println(pending.intercepted() === pending.intercepted())
            pending.intercepted().resume(Unit)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "InterceptedSourceBody",
            expected: "true\nok\ntrue\ntrue\ntrue\n42\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test
    func testUninterceptedCoroutineStartsOnlyOnResume() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.EmptyCoroutineContext
        import kotlin.coroutines.resume
        import kotlin.coroutines.intrinsics.createCoroutineUnintercepted
        import kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn

        // Top-level counters: a suspend lambda that captures a local `var` currently
        // crashes when started through the unintercepted-coroutine entry-point ABI.
        var starts = 0
        var completed = 0

        fun main() {
            val completion = Continuation<Int>(EmptyCoroutineContext) { result ->
                completed = result.getOrThrow()
            }
            val function: suspend () -> Int = {
                starts++
                7
            }
            val pending = function.createCoroutineUnintercepted(completion)
            println(starts)
            pending.resume(Unit)
            println("$starts:$completed")
            println(function.startCoroutineUninterceptedOrReturn(completion))
            println(starts)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "SuspendFunction0UninterceptedSource",
            expected: "0\n1:7\n7\n2\n"
        )
    }
}
#endif
