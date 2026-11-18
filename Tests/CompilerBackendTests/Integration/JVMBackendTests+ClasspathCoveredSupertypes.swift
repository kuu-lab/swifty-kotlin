#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    /// Classpath stubs must keep Kotlin supertypes whose classes are provided
    /// by the frontend's bundled sources rather than any jar on the classpath
    /// (e.g. `kotlin.coroutines.AbstractCoroutineContextElement` /
    /// `ContinuationInterceptor` for kotlinx-coroutines' `CoroutineDispatcher`).
    /// Without those edges `Dispatchers.IO` is not a `CoroutineContext` and
    /// `withContext(Dispatchers.IO)` fails semantic analysis.
    @Test
    func classpathStubKeepsCoveredKotlinSupertypes() throws {
        try withWorkspace { root in
            let fixturePath = root.appendingPathComponent("Fixture.kt")
            let fixture = """
                package fixture

                import kotlin.coroutines.AbstractCoroutineContextElement
                import kotlin.coroutines.Continuation
                import kotlin.coroutines.ContinuationInterceptor
                import kotlin.coroutines.CoroutineContext

                class ProbeDispatcher private constructor() :
                    AbstractCoroutineContextElement(ContinuationInterceptor.Key),
                    ContinuationInterceptor {
                    companion object {
                        val IO: ProbeDispatcher = ProbeDispatcher()
                    }

                    override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> =
                        continuation
                }
                """
            try fixture.write(to: fixturePath, atomically: true, encoding: .utf8)
            let kotlinc = try jvmTool("kotlinc", ["Fixture.kt", "-d", "fixture.jar"], root: root)
            try #require(kotlinc.exitCode == 0, "\(kotlinc.stderr)")

            let consumer = """
                import fixture.ProbeDispatcher
                import kotlin.coroutines.ContinuationInterceptor
                import kotlin.coroutines.CoroutineContext

                fun probeIOContext(): CoroutineContext = ProbeDispatcher.IO
                fun probeIOElement(): CoroutineContext.Element = ProbeDispatcher.IO
                fun probeIOInterceptor(): ContinuationInterceptor = ProbeDispatcher.IO
                """
            let (_, exit, diagnostics) = try m22Build(
                root: root,
                sources: [("Consumer.kt", consumer)],
                name: "consumer.jar",
                classpath: [root.appendingPathComponent("fixture.jar").path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
        }
    }
}
#endif
