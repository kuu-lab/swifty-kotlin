#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func coroutineLauncherFunctionValueAdapterPreservesCapturesAndReceiver() throws {
        let source = """
        import kotlinx.coroutines.*
        fun main() = runBlocking {
            val bonus = 7
            val block: suspend CoroutineScope.() -> Int = { bonus }
            println(async(block = block).await())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)
            let adapters = module.arena.declarations.compactMap { declaration -> KIRFunction? in
                guard case let .function(function) = declaration,
                      ctx.interner.resolve(function.name).hasPrefix("kk_coroutine_block_adapter_")
                else { return nil }
                return function
            }
            #expect(adapters.count >= 2)
            let capturedAdapter = try #require(adapters.first { $0.params.count == 1 })
            #expect(capturedAdapter.isSuspend)
            let scopeCall = try #require(capturedAdapter.body.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return ctx.interner.resolve(callee) == "kk_coroutine_current_scope"
            })
            guard case let .call(_, _, _, scope, _, _, _, _) = scopeCall else { return }
            let invocation = try #require(capturedAdapter.body.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return ctx.interner.resolve(callee).hasPrefix("kk_lambda_")
            })
            guard case let .call(_, _, arguments, _, _, _, _, _) = invocation else { return }
            #expect(arguments.count == 2)
            #expect(arguments.last == scope)
        }
    }

    @Test func testSuspendCoroutineUninterceptedOrReturnLoweringReturnsOnSuspendedToken() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let anyType = fixture.types.anyType

        let continuationSymbol = defineSemanticSymbol(
            in: fixture,
            kind: .interface,
            fqName: ["kotlin", "coroutines", "Continuation"]
        )
        let continuationType = fixture.types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(anyType)],
            nullability: .nonNull
        )))
        let blockType = fixture.types.make(.functionType(FunctionType(
            params: [continuationType],
            returnType: anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let suspendedExpr = appendTypedExpr(
            .call(
                callee: appendTypedExpr(
                    .nameRef(fixture.interner.intern("kk_coroutine_suspended"), range),
                    type: anyType,
                    fixture: fixture
                ),
                typeArgs: [],
                args: [],
                range: range
            ),
            type: anyType,
            fixture: fixture
        )
        let lambdaBody = suspendedExpr
        let lambdaExpr = appendTypedExpr(
            .lambdaLiteral(
                params: [fixture.interner.intern("cont")],
                body: lambdaBody,
                range: range
            ),
            type: blockType,
            fixture: fixture
        )
        let calleeExpr = appendTypedExpr(
            .nameRef(fixture.interner.intern("suspendCoroutineUninterceptedOrReturn"), range),
            type: anyType,
            fixture: fixture
        )
        let callExpr = appendTypedExpr(
            .call(
                callee: calleeExpr,
                typeArgs: [],
                args: [CallArgument(expr: lambdaExpr)],
                range: range
            ),
            type: anyType,
            fixture: fixture
        )

        fixture.bindings.markStdlibSpecialCallExpr(callExpr, kind: .suspendCoroutineUninterceptedOrReturn)

        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerCallExpr(
            callExpr,
            calleeExpr: calleeExpr,
            args: [CallArgument(expr: lambdaExpr)],
            ast: fixture.ast,
            sema: fixture.sema,
            arena: fixture.kirArena,
            interner: fixture.interner,
            propertyConstantInitializers: [:],
            instructions: &emit.instructions
        )

        let callees = extractCallees(from: emit.instructions, interner: fixture.interner)
        #expect(callees.contains("kk_coroutine_suspended"))
        #expect(emit.instructions.contains { instruction in
            if case .returnValue = instruction { return true }
            return false
        })
        #expect(emit.instructions.contains { instruction in
            if case .jumpIfEqual = instruction { return true }
            return false
        })
    }
}
#endif
