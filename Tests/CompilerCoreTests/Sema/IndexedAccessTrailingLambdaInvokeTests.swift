#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct IndexedAccessTrailingLambdaInvokeTests {
    private func context(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path],
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test func callChainInvokeContextualizesTrailingLambda() throws {
        let ctx = context("""
        class A(val s: Int) {
            operator fun get(i: Int): A = A(s + i)
            operator fun invoke(builder: A.() -> Int): Int = builder()
        }
        fun x(y: Int): A = A(y)
        fun foo(): Int = x(1)[42] { s }

        class Box(val text: Int) {
            operator fun get(index: Int): Box = this
            operator fun invoke(block: Box.() -> Int): Int = block()
        }
        fun minimal(): Int = Box(7)[0] { text }
        fun explicitIndexedInvoke(): Int = Box(7)[0].invoke { text }
        fun explicitDirectInvoke(): Int = Box(7).invoke { text }
        fun directCallInvoke(): Int = Box(7)({ text })
        """)

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let indexedInvokeCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .call(callee, _, args, _) = ast.arena.expr(id),
                  case .indexedAccess = ast.arena.expr(callee),
                  args.last?.isTrailingLambda == true
            else {
                return nil
            }
            return id
        }
        #expect(indexedInvokeCalls.count == 2)
        #expect(indexedInvokeCalls.allSatisfy(sema.bindings.isInvokeOperatorCall))

        let directInvokeCall = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .call(callee, _, _, _) = ast.arena.expr(id),
                  case .call = ast.arena.expr(callee),
                  sema.bindings.isInvokeOperatorCall(id)
            else {
                return nil
            }
            return id
        }.first)
        #expect(sema.bindings.isInvokeOperatorCall(directInvokeCall))
    }
}
#endif
