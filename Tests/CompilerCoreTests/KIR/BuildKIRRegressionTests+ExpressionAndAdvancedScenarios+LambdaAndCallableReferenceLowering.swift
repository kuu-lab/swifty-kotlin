#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testBuildKIRObjectLiteralArgumentIsNotLoweredToUnitPlaceholder() throws {
        let source = """
        interface I
        fun consume(value: I): I = value
        fun main(): I {
            val instance = object : I {}
            return consume(instance)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
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
    }

    @Test func testBuildKIRLowersLambdaLiteralToGeneratedCallableAndPrependsCapturesOnCall() throws {
        let source = """
        fun main(): Int {
            val base = 40
            val add = { x -> base + x }
            return add(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
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
    }

    @Test func testBuildKIRCollectionHOFLambdaStillReceivesClosureParameter() throws {
        let source = """
        fun main(): Int {
            val values = listOf(1, 2, 3)
            return values.map { it + 1 }.first()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let generatedLambdaFunctions = findAllKIRFunctions(in: module).filter { function in
                ctx.interner.resolve(function.name).hasPrefix("kk_lambda_")
            }
            // Find the user's HOF lambda (2 params: closure + elem), not the bundled stdlib's require lambda
            let generatedFunction = try #require(generatedLambdaFunctions.last)
            #expect(generatedFunction.params.count == 2, "closure + elem")
            #expect(generatedFunction.params.first?.type == ctx.sema?.types.intType)
        }
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

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
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
    }

    @Test func testBuildKIRCallableValueCallRespectsParameterMappingBeforePrependingCaptures() throws {
        let source = """
        fun main(): Int {
            val base = 100
            val add = { a, b -> base + a + b }
            return add(1, 2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let addCallExprID = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExprID, _, _, _) = expr,
                      let calleeExpr = ast.arena.expr(calleeExprID),
                      case let .nameRef(calleeName, _) = calleeExpr
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "add"
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

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let sema = try #require(ctx.sema)
            let module = try #require(ctx.kir)
            let incSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                symbol.kind == .function && ctx.interner.resolve(symbol.name) == "inc"
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

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
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
    }

    // MARK: - P5-39: vararg call lowering / ABI regression tests
}
#endif
