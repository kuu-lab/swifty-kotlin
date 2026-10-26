@testable import CompilerCore
import Testing

@Suite(.serialized)
struct KUU3286SuspendExtensionMultipleContextTests {
    @Test
    func secondContextArgumentSurvivesSuspendExtensionCall() throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlin.ExperimentalContextParameters::class)
            import kotlin.coroutines.*

            context(u: Unit, s: String)
            suspend fun Int.foo(): String = "${this},${u},${s}"

            fun builder(c: suspend () -> Unit) {
                c.startCoroutine(object : Continuation<Unit> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<Unit>) {
                        result.getOrThrow()
                    }
                })
            }

            fun main() {
                var result = "fail"
                builder { with(Unit) { with("foo") { result = 42.foo() } } }
                println(result)
            }
            """,
            expectedOutput: "42,kotlin.Unit,foo\n",
            moduleName: "KUU3286SuspendExtensionMultipleContext"
        )
    }
}
