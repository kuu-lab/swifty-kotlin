#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct SuspendFunctionInvokeCallableReferenceTests {
    @Test func boundInvokeReferenceKeepsFunctionTypeAndSuspendness() throws {
        try withTemporaryFile(contents: """
        fun plain(action: () -> Unit) {
            val reference = action::invoke
            reference()
        }
        suspend fun suspending(suspendingAction: suspend () -> Unit) {
            val reference = suspendingAction::invoke
            reference()
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(ctx)

            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let references = ast.arena.exprs.indices.compactMap { index -> (ExprID, Bool)? in
                let expressionID = ExprID(rawValue: Int32(index))
                guard case let .callableRef(receiver?, member, _) = ast.arena.expr(expressionID),
                      ctx.interner.resolve(member) == "invoke",
                      case let .nameRef(name, _) = ast.arena.expr(receiver)
                else {
                    return nil
                }
                return (expressionID, ctx.interner.resolve(name) == "suspendingAction")
            }
            try #require(references.count == 2)

            for (reference, isSuspend) in references {
                let type = try #require(sema.bindings.exprType(for: reference))
                guard case let .functionType(function) = sema.types.kind(of: type) else {
                    Issue.record("A bound function invoke reference should have a function type.")
                    continue
                }
                #expect(function.params.isEmpty)
                #expect(function.returnType == sema.types.unitType)
                #expect(function.isCallableReference)
                #expect(function.isSuspend == isSuspend)
                #expect(!sema.bindings.isUnboundCallableRef(reference))

                let target = try #require(sema.bindings.identifierSymbol(for: reference))
                let expectedBridge = isSuspend ? "kk_suspend_function_invoke_0" : "kk_function_invoke_0"
                #expect(sema.symbols.externalLinkName(for: target) == expectedBridge)
            }

            let kir = try #require(ctx.kir)
            let dump = kir.dump(interner: ctx.interner, symbols: sema.symbols)
            #expect(dump.contains("kk_function_invoke_0"))
            #expect(dump.contains("kk_suspend_function_invoke_0"))
        }
    }
}
#endif
