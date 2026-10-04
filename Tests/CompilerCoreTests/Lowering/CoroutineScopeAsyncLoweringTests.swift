@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CoroutineScopeAsyncLoweringTests {
    @Test(arguments: ["DEFAULT", "LAZY", "ATOMIC", "UNDISPATCHED"])
    func sourceBuilderUsesReceiverContinuationAndTypedAwait(start: String) throws {
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
        let ctx = makeContextFromSource(source, allowDefaultStdlibLibrary: true)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        try LoweringPhase().run(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let callees = findAllKIRFunctions(in: module).flatMap {
            extractCallees(from: $0.body, interner: ctx.interner)
        }
        #expect(callees.contains("kk_coroutine_scope_async_with_cont"))
        #expect(callees.contains("kk_coroutine_launcher_arg_set"))
        #expect(!callees.contains("kk_coroutine_scope_launch"))
    }
}
