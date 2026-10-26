@testable import CompilerTestSupport
import Foundation
@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct SuspendCancellableCoroutineInferenceTests {
    @Test(arguments: [false, true])
    func sleepWhileInfersUnitFromFunctionValueArgument(fromSource: Bool) throws {
        let source = """
        import kotlin.coroutines.*
        import kotlinx.coroutines.*

        private inline fun <reified T : Any> trySuspend(task: T, crossinline s: () -> Boolean) {}

        private suspend inline fun <reified T : Any> sleepWhile(
            crossinline createTask: (Continuation<Unit>) -> T,
            crossinline shouldSleep: () -> Boolean
        ) {
            while (shouldSleep()) {
                suspendCancellableCoroutine { cont ->
                    trySuspend<T>(createTask(cont), shouldSleep)
                }
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let library: String?
            if fromSource {
                library = nil
            } else {
                TestStdlibCache.shared.prepare()
                library = try #require(CompilerOptions.defaultStdlibLibraryPath)
            }
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
            try runSema(ctx)
            try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "suspendCancellableCoroutine"
            }
            #expect(calls.count == 1)
            let call = try #require(calls.first)
            #expect(sema.bindings.exprType(for: call) == sema.types.unitType)
            #expect(sema.bindings.callBinding(for: call)?.substitutedTypeArguments == [sema.types.unitType])
        }
    }
}
