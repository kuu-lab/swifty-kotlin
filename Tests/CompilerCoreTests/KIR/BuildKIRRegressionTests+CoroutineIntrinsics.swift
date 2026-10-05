#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func suspendReceiverFunctionValueForwardedThroughHelperPreservesEnvironment() throws {
        let source = """
        import kotlinx.coroutines.*
        fun runValue(block: suspend CoroutineScope.() -> Int): Int = runBlocking(block = block)
        fun main() {
            val bonus = 7
            val block: suspend CoroutineScope.() -> Int = { bonus + 23 }
            println(runValue(block))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)
            let functions = module.arena.declarations.compactMap { $0.function }
            let adapters = functions.filter {
                ctx.interner.resolve($0.name).hasPrefix("kk_coroutine_block_adapter_")
            }
            #expect(adapters.count == 1)
            let adapter = try #require(adapters.first)
            #expect(adapter.isSuspend)
            #expect(adapter.params.count == 1)
            #expect(extractCallees(from: adapter.body, interner: ctx.interner)
                .contains("kk_suspend_function_invoke"))

            let helper = try #require(functions.first { ctx.interner.resolve($0.name) == "runValue" })
            #expect(!extractCallees(from: helper.body, interner: ctx.interner)
                .contains(where: { $0.hasPrefix("kk_function_create_") }))
            let launcherCall = try #require(helper.body.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return ctx.interner.resolve(callee) == "runBlocking"
            })
            guard case let .call(_, _, arguments, _, _, _, _, _) = launcherCall else { return }
            #expect(arguments.count == 2)
            #expect(module.arena.expr(arguments[0]) == .symbolRef(adapter.symbol))
            #expect(module.arena.expr(arguments[1]) == .symbolRef(helper.params[0].symbol))

            let main = try #require(functions.first { ctx.interner.resolve($0.name) == "main" })
            #expect(extractCallees(from: main.body, interner: ctx.interner).contains("kk_function_create_1"))

            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func suspendLambdaFunctionValueRetainsTypeAndDelayBridge() throws {
        let source = """
        import kotlinx.coroutines.*
        private suspend fun invokeBlock(block: suspend () -> Int): Int = block()
        fun main() = runBlocking {
            val block = suspend { delay(10); 42 }
            println(block())
            println(invokeBlock(block))
            val immediate = suspend { 43 }
            println(invokeBlock(immediate))
            val seed = 41
            val captured = suspend { delay(10); seed + 1 }
            println(captured())
            println(invokeBlock(captured))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let suspendCalls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "suspend"
            }
            #expect(suspendCalls.count == 3)
            for call in suspendCalls {
                let type = try #require(sema.bindings.exprType(for: call))
                guard case let .functionType(functionType) = sema.types.kind(of: type) else {
                    Issue.record("Expected a suspend function value")
                    continue
                }
                #expect(functionType.isSuspend)
                #expect(functionType.returnType == sema.types.intType)
                let callee = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
                #expect(sema.symbols.isSourceBackedSymbol(callee))
                #expect(sema.symbols.symbol(callee)?.fqName.map(ctx.interner.resolve) == ["kotlin", "suspend"])
                #expect(sema.symbols.functionSignature(for: callee)?.valueParameterAllowsNonLocalReturn == [false])
                guard case let .call(_, _, args, _) = ast.arena.expr(call) else { continue }
                let lambda = try #require(args.first?.expr)
                #expect(!sema.bindings.isCoroutineLauncherLambdaExpr(lambda))
                #expect(!sema.bindings.isCollectionHOFLambdaExpr(lambda))
            }
            let module = try #require(ctx.kir)
            let functions = module.arena.declarations.compactMap { declaration -> KIRFunction? in
                guard case let .function(function) = declaration else { return nil }
                return function
            }
            let delayFunctions = functions.filter { function in
                function.body.contains { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "kk_kxmini_delay"
                }
            }
            #expect(!delayFunctions.isEmpty)
            #expect(delayFunctions.allSatisfy { ctx.interner.resolve($0.name).hasPrefix("kk_suspend_") })
            #expect(!functions.contains { function in
                function.body.contains { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "delay"
                }
            })
        }
    }

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
            #expect(adapters.count == 1)
            let capturedAdapter = try #require(adapters.first { $0.params.count == 1 })
            #expect(capturedAdapter.isSuspend)
            let scopeCall = try #require(capturedAdapter.body.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return ctx.interner.resolve(callee) == "kk_coroutine_current_scope"
            })
            guard case let .call(_, _, _, scope, _, _, _, _) = scopeCall else { return }
            let invocation = try #require(capturedAdapter.body.first { instruction in
                guard case let .call(symbol?, _, _, _, _, _, _, _) = instruction else { return false }
                return module.arena.declarations.contains {
                    $0.function?.symbol == symbol && $0.function?.isSuspend == true
                }
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
