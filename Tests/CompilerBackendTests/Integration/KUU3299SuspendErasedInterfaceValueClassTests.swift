@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KUU3299SuspendErasedInterfaceValueClassTests {
    @Test
    func erasedGenericInterfaceRestoresSuspendValueClassResult() throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.*

            @JvmInline
            value class IC(val s: String)

            interface Base<T> {
                suspend fun g(): T
            }

            class D : Base<IC> {
                override suspend fun g(): IC = suspendCoroutine {
                    it.resume(IC("OK"))
                }
            }

            fun main() {
                val base: Base<*> = D()
                val work: suspend () -> Unit = {
                    println((base.g() as IC).s)
                }
                work.startCoroutine(object : Continuation<Unit> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<Unit>) {
                        result.getOrThrow()
                    }
                })
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3299SuspendErasedInterfaceValueClass",
            allowDefaultStdlibLibrary: true
        )
    }
}
