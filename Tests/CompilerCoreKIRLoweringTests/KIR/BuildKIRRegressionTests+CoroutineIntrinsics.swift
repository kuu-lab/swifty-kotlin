#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test
    func boundCallableReferenceToSuspendInlineLongExtensionBuildsKIR() throws {
        let source = """
        import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
        import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
        import kotlin.coroutines.resume

        suspend inline fun Long.longArgs(a: Long, b: Long, c: Long) =
            suspendCoroutineUninterceptedOrReturn<Long> {
                it.resume(this + a + b + c)
                COROUTINE_SUSPENDED
            }

        suspend fun main(): Long {
            val ref = 1L::longArgs
            return ref(1L, 1L, 1L)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors)")
        let module = try #require(ctx.kir)
        let main = try findKIRFunction(named: "main", in: module, interner: ctx.interner)
        #expect(main.isSuspend)
    }

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

            let helper = try #require(functions.first { $0.name == ctx.interner.intern("runValue") })
            #expect(!extractCallees(from: helper.body, interner: ctx.interner)
                .contains(where: { runtimeFunctionCreateCallees().contains($0) }))
            let launcherCall = try #require(helper.body.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return callee == ctx.interner.intern("runBlocking$default")
            })
            guard case let .call(_, _, arguments, _, _, _, _, _) = launcherCall else { return }
            // `runBlocking(block = block)` skips `context`, so the source-backed
            // builder is reached through `runBlocking$default`: a zero
            // placeholder for the omitted context, the block value itself,
            // then the default-args mask word.
            #expect(arguments.count == 3)
            #expect(module.arena.expr(arguments[0]) == .intLiteral(0))
            #expect(module.arena.expr(arguments[1]) == .symbolRef(helper.params[0].symbol))
            #expect(module.arena.expr(arguments[2]) == .intLiteral(1))
            // The stored suspend value crosses the launcher boundary as-is —
            // no `kk_coroutine_block_adapter` re-packaging — so its capture
            // environment rides inside the boxed function value.
            #expect(try findKIRCoroutineBlockAdapters(in: ctx).isEmpty)

            let main = try #require(functions.first { $0.name == KnownCompilerNames(interner: ctx.interner).main })
            #expect(extractCallees(from: main.body, interner: ctx.interner).contains(runtimeCallee(.functionCreate1)))

            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func suspendLambdaFunctionValueRetainsTypeAndDelayBridge() throws {
        let source = try diffCaseSource("suspend_lambda_delay_function_value.kt", file: #filePath)
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
                return name == ctx.interner.intern("suspend")
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
                    return callee == ctx.interner.intern(runtimeCallee(.kxminiDelay))
                }
            }
            #expect(!delayFunctions.isEmpty)
            let loweredDelayFunctions = delayFunctions.allSatisfy { function in
                guard !function.isSuspend, let continuation = function.params.last,
                      continuation.type == function.returnType,
                      let parameter = sema.symbols.symbol(continuation.symbol),
                      parameter.kind == .valueParameter,
                      parameter.flags.contains(.synthetic)
                else { return false }
                let owners = sema.symbols.lookupAll(fqName: Array(parameter.fqName.dropLast()))
                    .compactMap { sema.symbols.symbol($0) }
                return owners.contains { owner in
                    owner.kind == .function && owner.flags.contains(.synthetic)
                        && (owner.id == function.symbol || owner.name == function.name)
                }
            }
            #expect(loweredDelayFunctions, "Delay bridges must belong to lowered coroutine functions with a synthetic continuation")
            #expect(!functions.contains { function in
                function.body.contains { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return callee == KnownCompilerNames(interner: ctx.interner).delay
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
            // The bundled `CoroutineScope.async` is an external member call:
            // the runBlocking literal forwards its own `this` receiver and the
            // stored `block` boxed as an ordinary suspend function value — no
            // `kk_coroutine_block_adapter`/`kk_coroutine_current_scope` read.
            let scopeAsyncCallee = ctx.interner.intern("kk_coroutine_scope_async")
            let launcherLambda = try #require(findKIRLambdaFunctions(in: ctx).first { function in
                function.body.contains { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return callee == scopeAsyncCallee
                }
            })
            #expect(try findKIRCoroutineBlockAdapters(in: ctx).isEmpty)
            let asyncCall = try #require(launcherLambda.body.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return callee == scopeAsyncCallee
            })
            guard case let .call(_, _, asyncArguments, _, _, _, _, _) = asyncCall else { return }
            #expect(asyncArguments.count == 4)
            #expect(module.arena.expr(asyncArguments[0]) == .symbolRef(launcherLambda.params[0].symbol))
            let createCall = try #require(launcherLambda.body.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return callee == ctx.interner.intern(runtimeFunctionCreateCallee(arity: 1))
            })
            guard case let .call(_, _, createArguments, createResult, _, _, _, _) = createCall else { return }
            #expect(asyncArguments.last == createResult)
            let adapter = try referencedKIRFunction(try #require(createArguments.first), in: module)
            #expect(adapter.isSuspend)
            #expect(adapter.params.count == 2)
            // The adapter's closure env carries the capture, while the
            // launcher-supplied scope receiver reaches the lambda through a
            // checked cast of the adapter's receiver parameter (KUU-3535).
            let captureLoad = try #require(adapter.body.compactMap { instruction -> KIRExprID? in
                guard case let .call(_, callee, args, result, _, _, _, _) = instruction,
                      callee == ctx.interner.intern(runtimeCallee(.arrayGetInbounds)),
                      case .intLiteral(2) = module.arena.expr(args[1])
                else { return nil }
                return result
            }.first)
            let invocation = try #require(adapter.body.first { instruction in
                guard case let .call(symbol?, _, _, _, _, _, _, _) = instruction else { return false }
                return module.arena.declarations.contains {
                    $0.function?.symbol == symbol && $0.function?.isSuspend == true
                }
            })
            guard case let .call(_, _, arguments, _, _, _, _, _) = invocation else { return }
            #expect(arguments.count == 2)
            #expect(adapter.body.contains { instruction in
                guard case let .call(_, _, args, result, _, _, _, _) = instruction else { return false }
                return result == arguments[0] && args.first == captureLoad
            })
            let receiverCastOperand = try #require(adapter.body.compactMap { instruction -> KIRExprID? in
                guard case let .call(_, callee, args, result, _, _, _, _) = instruction,
                      callee == ctx.interner.intern("kk_op_cast"),
                      result == arguments[1]
                else { return nil }
                return args.first
            }.first)
            #expect(
                resolveForwardedSymbolRef(receiverCastOperand, in: adapter.body, module: module)
                    == adapter.params[1].symbol
            )
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
                    .nameRef(fixture.interner.intern(runtimeCallee(.coroutineSuspended)), range),
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
            .nameRef(KnownCompilerNames(interner: fixture.interner).suspendCoroutineUninterceptedOrReturn, range),
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
        #expect(callees.contains(runtimeCallee(.coroutineSuspended)))
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
