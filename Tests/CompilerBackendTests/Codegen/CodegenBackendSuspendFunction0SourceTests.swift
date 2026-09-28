#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CodegenBackendSuspendFunction0SourceTests {
    @Test
    func testUninterceptedCoroutineStartsOnlyOnResume() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.EmptyCoroutineContext
        import kotlin.coroutines.resume
        import kotlin.coroutines.intrinsics.createCoroutineUnintercepted
        import kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn

        fun main() {
            var starts = 0
            var completed = 0
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
