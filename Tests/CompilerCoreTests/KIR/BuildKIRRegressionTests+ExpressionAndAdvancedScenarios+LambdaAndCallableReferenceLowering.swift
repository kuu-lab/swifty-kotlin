#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test func testBuildKIRMaterializesNominalFunctionArguments() throws {
        let source = """
        fun widen(f: Function1<Int, String>): (Int) -> String = f
        fun main() {
            val h: Function1<Int, String> = { it.toString() }
            println(widen(h)(9))
            println(widen { it.toString() }(10))
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let boxedValues = Set(body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_function_create_1"
            else { return nil }
            return result
        })
        let widenArguments = body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "widen"
            else { return nil }
            return arguments.first
        }
        #expect(widenArguments.count == 2)
        #expect(widenArguments.allSatisfy(boxedValues.contains))
    }

    @Test func testBuildKIRInfersGenericNominalFunctionArguments() throws {
        let source = """
        fun <T, R> nominal(f: Function1<T, R>): (T) -> R = f
        fun <T> ordinary(f: (T) -> String, value: T): String = f(value)
        fun main() {
            val offset = 20
            println(nominal<Int, Int> { it + offset }(5))
            val h: Function1<Int, String> = { it.toString() }
            println(ordinary(h, 6))
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func testBuildKIRMaterializesNominalPrimitiveOperatorReferences() throws {
        let ctx = makeContextFromSource("""
        fun apply(op: Function2<Int, Int, Int>): Int = op(2, 3)
        fun main() {
            val plus: Function2<Int, Int, Int> = Int::plus
            val times: Function2<Long, Long, Long> = Long::times
            println(plus(2, 3))
            println(times(7L, 6L))
            println(apply(Int::times))
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: 0 ... 5)
    func testBuildKIRRegistersAritySpecificNominalInvokeABI(arity: Int) throws {
        let arguments = Array(repeating: "Int", count: arity + 1).joined(separator: ", ")
        let parameters = (0 ..< arity).map { "p\($0)" }.joined(separator: ", ")
        let arrow = arity == 0 ? "" : "\(parameters) -> "
        let values = Array(repeating: "1", count: arity).joined(separator: ", ")
        let ctx = makeContextFromSource("""
        fun main() {
            val f: Function\(arity)<\(arguments)> = { \(arrow)7 }
            println(f(\(values)))
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let owner = try #require(sema.types.functionNInterfaceSymbols[arity])
        let symbol = try #require(sema.symbols.symbol(owner))
        let invoke = try #require(sema.symbols.lookup(fqName: symbol.fqName + [ctx.interner.intern("invoke")]))
        let linkName = arity == 1 ? "kk_function_invoke" : "kk_function_invoke_\(arity)"
        #expect(sema.symbols.externalLinkName(for: invoke) == linkName)
    }

    @Test func testBuildKIRCompareValuesByVarargSelectorsAreMaterialized() throws {
        let ctx = makeContextFromSource("""
        data class P(val n: String, val a: Int)
        fun name(p: P): String = p.n
        fun main(): Int = compareValuesBy(P("a", 1), P("a", 2), ::name, { it.a }, { it.n }, { it.a })
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let materialized = body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_function_create_1"
            else { return nil }
            return result
        }
        let stored = body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_array_set"
            else { return nil }
            return arguments[2]
        }
        #expect(materialized.count == 4)
        #expect(Array(stored.suffix(4)) == materialized)
    }

    @Test func testBuildKIRImportedCompareValuesByCallableReferenceIsMaterialized() throws {
        let ctx = makeContextFromSource("""
        data class P(val n: String, val a: Int)
        fun name(p: P): String = p.n
        fun main(): Int = compareValuesBy(P("a", 1), P("a", 2), ::name, { it.a })
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let materialized = try #require(body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_function_create_1"
            else { return nil }
            return result
        }.first)
        let call = try #require(body.first { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
            return ctx.interner.resolve(callee) == "compareValuesBy"
        })
        if case let .call(_, _, arguments, _, _, _, _, _) = call {
            #expect(arguments[2] == materialized)
        }
    }

    @Test func testBuildKIRInlineCallableReferencesUseErasedFunctionValueAdapters() throws {
        let source = """
        fun visit(key: String, value: Int) { println("$key$value") }
        inline fun <K, V> visitPair(key: K, value: V, action: (K, V) -> Unit) {
            action(key, value)
        }
        fun main() {
            val stored = ::visit
            visitPair("a", 1, ::visit)
            visitPair("b", 2, stored)
            visitPair("c", 3) { key, value -> println("$key$value") }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let materializedCallbacks = body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_function_create_2"
            else { return nil }
            return result
        }
        let callbacks = body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "visitPair"
            else { return nil }
            return arguments.last
        }
        #expect(materializedCallbacks.count == 2)
        #expect(callbacks.count == 3)
        #expect(Array(callbacks.prefix(2)) == materializedCallbacks)
        let literalCallback = try #require(callbacks.last)
        guard case .symbolRef? = module.arena.expr(literalCallback) else {
            Issue.record("inline lambda literals must remain directly expandable")
            return
        }
    }

    @Test func testBuildKIRObjectLiteralArgumentIsNotLoweredToUnitPlaceholder() throws {
        let source = """
        interface I
        fun consume(value: I): I = value
        fun main(): I {
            val instance = object : I {}
            return consume(instance)
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let consumeCall = try #require(mainBody.first { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                return false
            }
            return ctx.interner.resolve(callee) == "consume"
        })
        guard case let .call(_, _, arguments, _, _, _, _, _) = consumeCall else {
            Issue.record("Expected call instruction for consume(instance).")
            return
        }
        let objectArgument = try #require(arguments.first)
        let objectArgumentExpr = try #require(module.arena.expr(objectArgument))
        if case .unit = objectArgumentExpr {
            Issue.record("object literal must not be lowered to .unit placeholder at call sites.")
        }
    }

    @Test func testBuildKIRLowersLambdaLiteralToGeneratedCallableAndPrependsCapturesOnCall() throws {
        let source = """
        fun main(): Int {
            val base = 40
            val add = { x -> base + x }
            return add(2)
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let lambdaCall = try #require(mainBody.first { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                return false
            }
            return ctx.interner.resolve(callee).hasPrefix("kk_function_value_adapter_")
        })

        guard case let .call(callSymbol, callee, arguments, _, _, _, _, _) = lambdaCall else {
            Issue.record("Expected lowered lambda call in main.")
            return
        }
        #expect(callSymbol != nil)
        #expect(ctx.interner.resolve(callee).hasPrefix("kk_function_value_adapter_"))
        #expect(arguments.count == 2, "Closure-backed callable-value calls should pass closure object plus explicit args.")
        if case .unit? = module.arena.expr(arguments[0]) {
            Issue.record("Expected first lambda call argument to be a closure object reference.")
            return
        }
        guard case .intLiteral(2)? = module.arena.expr(arguments[1]) else {
            Issue.record("Expected second lambda call argument to be the explicit call argument.")
            return
        }
        let callNames = extractCallees(from: mainBody, interner: ctx.interner)
        #expect(callNames.contains("kk_object_new"))
        #expect(callNames.contains("kk_array_set"))
        #expect(callNames.contains("kk_function_create_1"))

        let adapterFunction = try #require(findAllKIRFunctions(in: module).first { function in
            ctx.interner.resolve(function.name).hasPrefix("kk_function_value_adapter_")
        })
        let adapterCallNames = extractCallees(from: adapterFunction.body, interner: ctx.interner)
        #expect(adapterCallNames.contains("kk_unbox_int"))

        let generatedLambdaFunctions = findAllKIRFunctions(in: module).filter { function in
            ctx.interner.resolve(function.name).hasPrefix("kk_lambda_")
        }
        #expect(!(generatedLambdaFunctions.isEmpty))
        if let generatedSymbol = callSymbol,
           let generatedFunction = generatedLambdaFunctions.first(where: { $0.symbol == generatedSymbol })
        {
            #expect(generatedFunction.params.count == 2, "capture + elem")
        }
    }

    @Test func testBuildKIRLambdaCapturesImplicitReceiverForUnqualifiedMemberCall() throws {
        let source = """
        class Counter(var value: Int) {
            fun step(): Int {
                value += 1
                return value
            }
            fun run(): Int {
                val bump: (Int) -> Unit = { step() }
                bump(0)
                return value
            }
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let lambdaFunction = try #require(findAllKIRFunctions(in: module).first { function in
            ctx.interner.resolve(function.name).hasPrefix("kk_lambda_")
                && extractCallees(from: function.body, interner: ctx.interner).contains("step")
        })
        #expect(
            lambdaFunction.params.count == 2,
            "Unqualified member call inside a lambda is `this.step()`, so the receiver must be captured."
        )
    }

    @Test func testBuildKIRCollectionSourceHOFLambdaHasElementParameter() throws {
        let source = """
        fun main(): Int {
            val values = listOf(1, 2, 3)
            return values.map { it + 1 }.first()
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let generatedLambdaFunctions = findAllKIRFunctions(in: module).filter { function in
            ctx.interner.resolve(function.name).hasPrefix("kk_lambda_")
        }
        // Source-backed map uses an ordinary boxed lambda (1 param: element),
        // not the native collection-HOF (closureObj, elem) ABI.
        let generatedFunction = try #require(generatedLambdaFunctions.last)
        #expect(generatedFunction.params.count == 1, "single element param")
        #expect(generatedFunction.params.first?.type == ctx.sema?.types.intType)
    }

    @Test func testBuildKIRWorkerExecuteExpandsProducerAndJobLambdas() throws {
        let source = """
        import kotlin.native.concurrent.TransferMode
        import kotlin.native.concurrent.Worker

        fun probe(worker: Worker): Int {
            val future = worker.execute(TransferMode.SAFE, { 21 }) { it * 2 }
            return future.result
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let probeBody = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
        let callSummaries = probeBody.compactMap { instruction -> String? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                return nil
            }
            return "\(ctx.interner.resolve(callee)):\(arguments.count)"
        }.joined(separator: ", ")
        let executeCall = try #require(probeBody.first { instruction in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                return false
            }
            return ctx.interner.resolve(callee) == "kk_worker_execute" && arguments.count == 6
        }, "Expected kk_worker_execute with 6 args; calls: \(callSummaries)")

        guard case let .call(_, _, arguments, _, _, _, _, _) = executeCall else {
            Issue.record("Expected Worker.execute to lower to kk_worker_execute.")
            return
        }
        #expect(
            arguments.count == 6,
            "Worker.execute ABI should be worker, mode, producer fn/closure, job fn/closure."
        )
    }

    @Test func testBuildKIRCallableValueCallRespectsParameterMappingBeforePrependingCaptures() throws {
        let source = """
        fun main(): Int {
            val base = 100
            val add = { a, b -> base + a + b }
            return add(1, 2)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: ctx.options.inputs[0]))
        let addCallExprID = try #require(firstExprID(in: ast) { exprID, expr in
            guard case let .call(calleeExprID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeExprID),
                  case let .nameRef(calleeName, _) = calleeExpr
            else {
                return false
            }
            return ctx.interner.resolve(calleeName) == "add"
                && ast.arena.exprRange(exprID)?.start.file == sourceFileID
        })
        let existingBinding = try #require(sema.bindings.callableValueCalls[addCallExprID])
        sema.bindings.bindCallableValueCall(
            addCallExprID,
            binding: CallableValueCallBinding(
                target: existingBinding.target,
                functionType: existingBinding.functionType,
                parameterMapping: [0: 1, 1: 0]
            )
        )

        try BuildKIRPhase().run(ctx)

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let lambdaCall = try #require(mainBody.first { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                return false
            }
            return ctx.interner.resolve(callee).hasPrefix("kk_function_value_adapter_")
        })

        guard case let .call(_, _, arguments, _, _, _, _, _) = lambdaCall else {
            Issue.record("Expected callable-value call to lowered lambda target.")
            return
        }
        #expect(arguments.count == 3)
        if case .unit? = module.arena.expr(arguments[0]) {
            Issue.record("Expected closure object argument at index 0.")
            return
        }
        guard case .intLiteral(2)? = module.arena.expr(arguments[1]) else {
            Issue.record("Expected parameter mapping to reorder explicit args before call emission.")
            return
        }
        guard case .intLiteral(1)? = module.arena.expr(arguments[2]) else {
            Issue.record("Expected reordered second parameter argument.")
            return
        }
    }

    @Test func testBuildKIRNestedEscapingFunctionTypeComparesArithmeticBeforeReturn() throws {
        let source = """
        fun main() {
            val f: (Int) -> (String) -> Boolean = { m -> { s -> s.length * m > 10 } }
            println(f(2)("hello"))
            println(f(2)("hi"))
        }
        """

        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let innerLambda = try #require(findAllKIRFunctions(in: module).first { function in
            guard ctx.interner.resolve(function.name).hasPrefix("kk_lambda_") else {
                return false
            }
            let callNames = extractCallees(from: function.body, interner: ctx.interner)
            return callNames.contains("kk_op_mul") && callNames.contains("kk_op_gt")
        })
        let innerCallNames = extractCallees(from: innerLambda.body, interner: ctx.interner)
        #expect(innerCallNames.contains("__kk_string_struct_get_length"))
        #expect(innerCallNames.contains("kk_op_mul"))
        #expect(innerCallNames.contains("kk_op_gt"))

        let adapterFunction = try #require(findAllKIRFunctions(in: module).first { function in
            ctx.interner.resolve(function.name).hasPrefix("kk_function_value_adapter_")
        })
        let adapterCallNames = extractCallees(from: adapterFunction.body, interner: ctx.interner)
        #expect(
            adapterCallNames.contains { name in
                name.hasPrefix("kk_closure_invoke_") || name.hasPrefix("kk_lambda_")
            }
        )
    }

    @Test func testSyntheticLambdaSymbolGenerationNeverUsesZeroOrInvalidSentinel() {
        let loweringCtx = KIRLoweringContext()
        let zeroExprSymbol = loweringCtx.syntheticLambdaSymbol(for: ExprID(rawValue: 0))
        let maxExprSymbol = loweringCtx.syntheticLambdaSymbol(for: ExprID(rawValue: Int32.max))

        #expect(zeroExprSymbol == loweringCtx.syntheticLambdaSymbol(for: ExprID(rawValue: 0)))
        #expect(zeroExprSymbol.rawValue < 0)
        #expect(zeroExprSymbol.rawValue != 0)
        #expect(zeroExprSymbol != .invalid)

        #expect(maxExprSymbol.rawValue < 0)
        #expect(maxExprSymbol.rawValue != 0)
        #expect(maxExprSymbol != .invalid)
        #expect(maxExprSymbol != zeroExprSymbol)
    }

    @Test func testBuildKIRLowersCallableRefToCallableSymbolValue() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main(): Int {
            val f = ::inc
            return f(2)
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let incSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function
                && symbol.declSite != nil
                && ctx.interner.resolve(symbol.name) == "inc"
                && sema.symbols.functionSignature(for: symbol.id)?.receiverType == nil
        })?.id)

        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let incCall = try #require(mainBody.first { instruction in
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else {
                return false
            }
            return symbol == incSymbol
        })

        guard case let .call(callSymbol, callee, arguments, _, _, _, _, _) = incCall else {
            Issue.record("Expected callable reference call to inc.")
            return
        }
        #expect(callSymbol == incSymbol)
        #expect(ctx.interner.resolve(callee) == "inc")
        #expect(arguments.count == 1)
        guard case .intLiteral(2)? = module.arena.expr(arguments[0]) else {
            Issue.record("Expected callable reference call to forward the explicit argument.")
            return
        }
    }

    @Test func testImplicitInterfaceCallableRefUsesVirtualDispatch() throws {
        let source = """
        interface Writer { fun flush(): Int }
        class BufferedWriter : Writer { override fun flush(): Int = 42 }
        fun flush(): Int = 7
        fun Writer.flushLater(): () -> Int = ::flush
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let interfaceFlush = try #require(sema.symbols.allSymbols().first { symbol in
            symbol.kind == .function
                && ctx.interner.resolve(symbol.name) == "flush"
                && sema.symbols.parentSymbol(for: symbol.id).flatMap { sema.symbols.symbol($0) }?.fqName
                    == [ctx.interner.intern("Writer")]
        }?.id)
        // The bound reference is lowered to a helper function that performs the
        // virtual call; its name is an implementation detail, so find it by body.
        let wrapper = try #require(findAllKIRFunctions(in: module).first { function in
            function.body.contains { instruction in
                if case let .virtualCall(symbol, _, _, _, _, _, _, _) = instruction {
                    return symbol == interfaceFlush
                }
                return false
            }
        })
        #expect(wrapper.params.count == 1, "Bound interface reference must capture its receiver.")
        #expect(!wrapper.body.contains { instruction in
            if case let .call(symbol, _, _, _, _, _, _, _) = instruction {
                return symbol == interfaceFlush
            }
            return false
        })
        let flushLaterBody = try findKIRFunctionBody(named: "flushLater", in: module, interner: ctx.interner)
        #expect(flushLaterBody.contains { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee) == "kk_function_create_0"
            }
            return false
        }, "A bound reference returned from a function must carry its receiver at runtime.")
    }

    @Test func testImplicitInterfaceCallableRefSamThunkUsesVirtualDispatch() throws {
        let source = """
        interface Writer { fun flush(): Int }
        class BufferedWriter : Writer { override fun flush(): Int = 42 }
        fun flush(): Int = 7
        fun interface Action { fun run(): Int }
        fun Writer.asAction(): Action = Action(::flush)
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let interfaceFlush = try #require(sema.symbols.allSymbols().first { symbol in
            symbol.kind == .function
                && ctx.interner.resolve(symbol.name) == "flush"
                && sema.symbols.parentSymbol(for: symbol.id).flatMap { sema.symbols.symbol($0) }?.fqName
                    == [ctx.interner.intern("Writer")]
        }?.id)
        let allFunctions = findAllKIRFunctions(in: module)
        #expect(allFunctions.contains { function in
            ctx.interner.resolve(function.name).hasPrefix("kk_sam_ref_thunk_")
        })
        // The SAM thunk reaches the interface member through a virtual call
        // (directly or via the bound-reference helper), never a direct call.
        #expect(allFunctions.contains { function in
            function.body.contains { instruction in
                if case let .virtualCall(symbol, _, _, _, _, _, _, _) = instruction {
                    return symbol == interfaceFlush
                }
                return false
            }
        })
        #expect(!allFunctions.contains { function in
            function.body.contains { instruction in
                if case let .call(symbol, _, _, _, _, _, _, _) = instruction {
                    return symbol == interfaceFlush
                }
                return false
            }
        })
    }

    @Test func testSamWrapperPreservesCallbackThrowingContract() throws {
        let source = """
        fun interface Action { fun run(): Int }
        fun action(callback: () -> Int): Action = Action { callback() }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)

        let module = try #require(ctx.kir)
        let wrapper = try #require(findAllKIRFunctions(in: module).first { function in
            ctx.interner.resolve(function.name) == "run"
                && function.body.contains { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return ctx.interner.resolve(callee).hasPrefix("kk_lambda_")
                    }
                    return false
                }
        })
        let throwingCalls = wrapper.body.compactMap { instruction -> Bool? in
            guard case let .call(_, callee, _, _, canThrow, _, _, _) = instruction,
                  ctx.interner.resolve(callee).hasPrefix("kk_lambda_")
            else { return nil }
            return canThrow
        }
        #expect(throwingCalls == [true])
    }

    @Test func testLocalCallableValueShadowsSameNamedStdlibExtension() throws {
        let source = """
        fun main(): Int {
            var counter = 0
            val inc = { counter++ }
            inc()
            inc()
            return counter
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError, "Local callable value should shadow Char.inc: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableValueCalls = ast.arena.exprs.indices.compactMap { index -> CallableValueCallBinding? in
            let exprID = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(exprID, in: ctx),
                  case .call = ast.arena.expr(exprID)
            else { return nil }
            return sema.bindings.callableValueCallBinding(for: exprID)
        }
        #expect(callableValueCalls.count == 2)
        #expect(callableValueCalls.allSatisfy { binding in
            if case .localValue = binding.target { return true }
            return false
        })
    }

    @Test func testNonCallableLocalDoesNotShadowSameNamedStdlibFunction() throws {
        let source = """
        fun main(): Int {
            val emptyList = emptyList<Int>()
            val emptyStrings = emptyList<String>()
            return emptyList.size + emptyStrings.size
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "A non-callable local should not hide a same-named function: \(ctx.diagnostics.diagnostics)"
        )
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let emptyListCalls = ast.arena.exprs.indices.compactMap { index -> CallBinding? in
            let exprID = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(exprID, in: ctx),
                  case let .call(callee, _, _, _) = ast.arena.expr(exprID),
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  ctx.interner.resolve(name) == "emptyList"
            else { return nil }
            return sema.bindings.callBinding(for: exprID)
        }
        #expect(emptyListCalls.count == 2)
        #expect(emptyListCalls.allSatisfy { binding in
            guard let symbol = sema.symbols.symbol(binding.chosenCallee) else { return false }
            return symbol.kind == .function && ctx.interner.resolve(symbol.name) == "emptyList"
        })
    }

    @Test func testBuildKIRPrependsBoundCallableRefReceiverAsCaptureArgument() throws {
        let source = """
        class Box {
            fun plus(x: Int): Int = x
        }
        fun main(box: Box): Int {
            val f = box::plus
            return f(7)
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let plusSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function && ctx.interner.resolve(symbol.name) == "plus"
        })?.id)

        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        // REFL-003: After callable ref tagging, look for the plus call
        // by either symbol match or callee name match.
        let plusCall = try #require(mainBody.first { instruction in
            guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else {
                return false
            }
            return symbol == plusSymbol || ctx.interner.resolve(callee) == "plus"
        })

        guard case let .call(_, callee, arguments, _, _, _, _, _) = plusCall else {
            Issue.record("Expected bound callable reference to lower to plus call.")
            return
        }
        #expect(ctx.interner.resolve(callee) == "plus")
        #expect(arguments.count == 2)
        guard case let .symbolRef(receiverSymbol)? = module.arena.expr(arguments[0]),
              let receiver = sema.symbols.symbol(receiverSymbol)
        else {
            Issue.record("Expected first argument to be captured receiver symbol.")
            return
        }
        #expect(ctx.interner.resolve(receiver.name) == "box")
        guard case .intLiteral(7)? = module.arena.expr(arguments[1]) else {
            Issue.record("Expected second argument to be call-site argument.")
            return
        }
    }

    // MARK: - P5-39: vararg call lowering / ABI regression tests
}
#endif
