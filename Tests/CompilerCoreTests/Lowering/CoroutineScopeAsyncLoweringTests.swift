@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CoroutineScopeAsyncLoweringTests {
    @Test(arguments: ["DEFAULT", "LAZY", "ATOMIC", "UNDISPATCHED"], [false, true])
    func sourceBuilderUsesReceiverContinuationAndTypedAwait(start: String, useArtifact: Bool) throws {
        let source = """
        import kotlinx.coroutines.*
        fun main() = runBlocking {
            val scope = CoroutineScope(SupervisorJob())
            val captured = 41
            val deferred = scope.async(start = CoroutineStart.\(start)) { captured + 1 }
            val result: Int = deferred.await()
            println(result + 1)
            scope.cancel()
        }
        """
        let ctx = makeContextFromSource(source, allowDefaultStdlibLibrary: useArtifact)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        try LoweringPhase().run(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let callees = findAllKIRFunctions(in: module).flatMap {
            extractCallees(from: $0.body, interner: ctx.interner)
        }
        #expect(callees.contains(LoweringTestRuntime.name("coroutine_scope_async_with_cont")))
        #expect(callees.contains(LoweringTestRuntime.name("coroutine_launcher_arg_set")))
        #expect(!callees.contains(LoweringTestRuntime.name("coroutine_scope_launch")))
    }
    @Test(arguments: [false, true])
    func launchContextUsesReceiverContinuation(useArtifact: Bool) throws {
        let ctx = makeContextFromSource("""
        import kotlin.coroutines.*
        import kotlinx.coroutines.*
        fun main() = runBlocking {
            val context: CoroutineContext = CoroutineName("child")
            val captured = 41
            launch(context, CoroutineStart.LAZY) { println(captured + 1) }.join()
            this.launch(context) { println(this.coroutineContext.job.isActive) }.join()
            val block: suspend CoroutineScope.() -> Unit = { println(captured) }
            this.launch(context, block = block).join()
        }
        """, allowDefaultStdlibLibrary: useArtifact)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        try LoweringPhase().run(ctx)
        let module = try #require(ctx.kir)
        let callees = findAllKIRFunctions(in: module).flatMap {
            extractCallees(from: $0.body, interner: ctx.interner)
        }
        #expect(callees.contains(LoweringTestRuntime.name("coroutine_scope_launch_context_with_cont")))
        #expect(callees.contains(LoweringTestRuntime.name("coroutine_scope_launch_context")))
        #expect(callees.contains(LoweringTestRuntime.name("coroutine_launcher_arg_set")))
        #expect(!callees.contains(LoweringTestRuntime.name("coroutine_scope_launch")))
    }

}
