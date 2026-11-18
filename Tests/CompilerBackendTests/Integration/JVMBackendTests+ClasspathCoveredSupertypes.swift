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

    /// Lazy classpath loading must treat types that appear only inside a
    /// covered Kotlin supertype's type arguments as dependencies, or the
    /// emitted stub references a class that was never injected.
    @Test
    func lazyCoveredSupertypeTypeArgumentsJoinDependencyClosure() throws {
        try withWorkspace { root in
            let fixture = """
                package fixture

                import kotlin.coroutines.CoroutineContext

                class Payload : CoroutineContext.Element {
                    override val key: CoroutineContext.Key<*> get() = PayloadKey
                }

                object PayloadKey : CoroutineContext.Key<Payload>
                """
            try fixture.write(to: root.appendingPathComponent("Fixture.kt"), atomically: true, encoding: .utf8)
            let kotlinc = try jvmTool("kotlinc", ["Fixture.kt", "-d", "fixture.jar"], root: root)
            try #require(kotlinc.exitCode == 0, "\(kotlinc.stderr)")

            let consumerPath = root.appendingPathComponent("Consumer.kt").path
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "LazyCoveredSupertypeTest",
                    inputs: [consumerPath],
                    outputPath: root.appendingPathComponent("out").path,
                    emit: .jvmJar,
                    target: .hostDefault(),
                    includeStdlib: false,
                    allowDefaultStdlibLibrary: false
                ),
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            // Covered Kotlin supertypes come from bundled sources; this
            // stand-in keeps `inject(into:)` off the stdlib resources.
            _ = ctx.sourceManager.addFile(
                path: "<kswiftk-jvm>/kotlin/coroutines/CoroutineContext.kt",
                contents: Data("""
                package kotlin.coroutines

                interface CoroutineContext {
                    interface Element
                    interface Key<B : Element>
                }
                """.utf8)
            )
            _ = ctx.sourceManager.addFile(path: consumerPath, contents: Data("""
            import fixture.PayloadKey

            fun probe() = PayloadKey
            """.utf8))
            let index = try JVMClasspathIndex.load(
                [root.appendingPathComponent("fixture.jar").path],
                automaticLazyClasspathMemberLimit: 1
            )
            try index.inject(into: ctx)

            let keyID = try #require(ctx.sourceManager.fileID(forPath: "<kswiftk-jvm-import>/fixture/PayloadKey.kt"))
            let keyStub = String(decoding: ctx.sourceManager.contents(of: keyID), as: UTF8.self)
            #expect(keyStub.contains("`fixture`.`Payload`"))
            #expect(ctx.sourceManager.fileID(forPath: "<kswiftk-jvm-import>/fixture/Payload.kt") != nil)
        }
    }
}
#endif
