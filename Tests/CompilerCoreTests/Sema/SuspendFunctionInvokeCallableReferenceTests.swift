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

    // KUU-3841: the bundled stdlib declares the synthesized KFunctionN /
    // KSuspendFunctionN reflection interfaces, so they import and accept the
    // matching suspend/non-suspend callable references.
    @Test func suspendCallableReferenceResolvesKSuspendFunctionInterfaces() throws {
        try withTemporaryFile(contents: """
        import kotlin.reflect.KFunction0
        import kotlin.reflect.KFunction1
        import kotlin.reflect.KSuspendFunction1
        import kotlin.reflect.KSuspendFunction22

        suspend fun foo(x: Int): Int = x
        fun bar(): Int = 0

        fun main() {
            val g: KSuspendFunction1<Int, Int> = ::foo
            val h: KFunction0<Int> = ::bar
            val i: suspend (Int) -> Int = ::foo
            val erased: Any = i
            val check = erased is KSuspendFunction1<*, *>
            // KSuspendFunctionN and KFunctionN stay disjoint statically —
            // assignments still reject the wrong family — yet `is` checks
            // between them compile because the families can intersect.
            val check2 = g is KFunction1<*, *>
            val check3 = i is KFunction1<*, *>
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func callableReferenceRejectsMismatchedKSuspendFunctionArity() throws {
        try withTemporaryFile(contents: """
        import kotlin.reflect.KSuspendFunction2

        suspend fun foo(x: Int): Int = x

        fun main() {
            val wrongArity: KSuspendFunction2<Int, Int, Int> = ::foo
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }
}
#endif
