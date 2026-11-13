#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// `Pipeline<*, TContext>.intercept` (Ktor's Pipeline.kt:522) delegates to the
/// member `Pipeline.intercept` with an untyped lambda. The scope lookup only
/// surfaces the extension, so the receiver-builder inference path claimed the
/// call and reported KSWIFTK-SEMA-INFER for its reified `TSubject`. A member on
/// the implicit receiver always shadows a same-named extension candidate.
@Suite
struct StarProjectedReceiverMemberShadowTests {
    @Test
    func memberShadowsExtensionOnStarProjectedReceiver() throws {
        let source = """
        open class PipelineContext<TSubject : Any, TContext : Any>(val pipeline: Pipeline<TSubject, TContext>)
        public typealias Inter<TSubject, TContext> =
            suspend PipelineContext<TSubject, TContext>.(TSubject) -> Unit
        class Phase
        open class Pipeline<TSubject : Any, TContext : Any>(vararg val phases: Phase) {
            fun intercept(phase: Phase, block: Inter<TSubject, TContext>) {}
        }
        inline fun <reified TSubject : Any, TContext : Any> Pipeline<*, TContext>.intercept(
            phase: Phase,
            noinline block: suspend PipelineContext<TSubject, TContext>.(TSubject) -> Unit
        ) {
            intercept(phase) interceptor@{ subject ->
                if (subject !is TSubject) return@interceptor
                val reinterpret = this as? PipelineContext<TSubject, TContext>
                reinterpret?.block(subject)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: true)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
