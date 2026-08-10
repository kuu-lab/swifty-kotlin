#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testBuildKIRLambdaAndCallableReferenceScenarios() throws {
        let sources = [
            """
            package sample0

            interface I

            fun consume0(value: I): I = value

            fun main0(): I {
                val instance = object : I {}
                return consume0(instance)
            }
            """,
            """
            package sample1

            fun main1(): Int {
                val base = 40
                val add = { x -> base + x }
                return add(2)
            }
            """,
            """
            package sample2

            fun main2(): Int {
                val values = listOf(1, 2, 3)
                return values.map { it + 1 }.first()
            }
            """,
            """
            package sample3

            import kotlin.native.concurrent.TransferMode
            import kotlin.native.concurrent.Worker

            fun probe3(worker: Worker): Int {
                val future = worker.execute(TransferMode.SAFE, { 21 }) { it * 2 }
                return future.result
            }
            """,
            """
            package sample4

            fun main4(): Int {
                val base = 100
                val add = { a, b -> base + a + b }
                return add(1, 2)
            }
            """,
            """
            package sample6

            fun inc6(x: Int): Int = x + 1

            fun main6(): Int {
                val f = ::inc6
                return f(2)
            }
            """,
            """
            package sample7

            class Box7 {
                fun plus7(x: Int): Int = x
            }

            fun main7(box: Box7): Int {
                val f = box::plus7
                return f(7)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            // source 4: mutate the callable-value binding to exercise parameter
            // mapping before the capture argument is prepended.
            let addCallExprID = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExprID, _, args, _) = expr,
                      let calleeExpr = ast.arena.expr(calleeExprID),
                      case let .nameRef(calleeName, _) = calleeExpr
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "add" && args.count == 2
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
            let interner = ctx.interner

            // source 0: object literal argument must not be lowered to .unit
            do {
                let mainBody = try findKIRFunctionBody(named: "main0", in: module, interner: interner)
                let consumeCall = try #require(mainBody.first { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                        return false
                    }
                    return interner.resolve(callee) == "consume0"
                })
                guard case let .call(_, _, arguments, _, _, _, _, _) = consumeCall else {
                    Issue.record("Expected call instruction for consume0(instance).")
                    return
                }
                let objectArgument = try #require(arguments.first)
                let objectArgumentExpr = try #require(module.arena.expr(objectArgument))
                if case .unit = objectArgumentExpr {
                    Issue.record("object literal must not be lowered to .unit placeholder at call sites.")
                }
            }

            // source 1: lambda literal lowering
            do {
                let mainBody = try findKIRFunctionBody(named: "main1", in: module, interner: interner)
                let lambdaCall = try #require(mainBody.first { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                        return false
                    }
                    return interner.resolve(callee).hasPrefix("kk_function_value_adapter_")
                })

                guard case let .call(callSymbol, callee, arguments, _, _, _, _, _) = lambdaCall else {
                    Issue.record("Expected lowered lambda call in main1.")
                    return
                }
                #expect(callSymbol != nil)
                #expect(interner.resolve(callee).hasPrefix("kk_function_value_adapter_"))
                #expect(arguments.count == 2, "Closure-backed callable-value calls should pass closure object plus explicit args.")
                if case .unit? = module.arena.expr(arguments[0]) {
                    Issue.record("Expected first lambda call argument to be a closure object reference.")
                    return
                }
                guard case .intLiteral(2)? = module.arena.expr(arguments[1]) else {
                    Issue.record("Expected second lambda call argument to be the explicit call argument.")
                    return
                }
                let callNames = extractCallees(from: mainBody, interner: interner)
                #expect(callNames.contains("kk_object_new"))
                #expect(callNames.contains("kk_array_set"))
                #expect(callNames.contains("kk_function_create_1"))

                let adapterFunction = try #require(findAllKIRFunctions(in: module).first { function in
                    interner.resolve(function.name).hasPrefix("kk_function_value_adapter_")
                })
                let adapterCallNames = extractCallees(from: adapterFunction.body, interner: interner)
                #expect(adapterCallNames.contains("kk_unbox_int"))

                let generatedLambdaFunctions = findAllKIRFunctions(in: module).filter { function in
                    interner.resolve(function.name).hasPrefix("kk_lambda_")
                }
                #expect(!(generatedLambdaFunctions.isEmpty))
                if let generatedSymbol = callSymbol,
                   let generatedFunction = generatedLambdaFunctions.first(where: { $0.symbol == generatedSymbol })
                {
                    #expect(generatedFunction.params.count == 2, "capture + elem")
                }
            }

            // source 2: collection HOF lambda has single element parameter
            do {
                let generatedLambdaFunctions = findAllKIRFunctions(in: module).filter { function in
                    interner.resolve(function.name).hasPrefix("kk_lambda_")
                }
                let generatedFunction = try #require(
                    generatedLambdaFunctions.first { function in
                        function.params.count == 1 && function.params.first?.type == ctx.sema?.types.intType
                    },
                    "Expected a source-backed map lambda with one Int element parameter"
                )
                #expect(generatedFunction.params.count == 1, "single element param")
                #expect(generatedFunction.params.first?.type == ctx.sema?.types.intType)
            }

            // source 3: Worker.execute expansion
            do {
                let probeBody = try findKIRFunctionBody(named: "probe3", in: module, interner: interner)
                let callSummaries = probeBody.compactMap { instruction -> String? in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                        return nil
                    }
                    return "\(interner.resolve(callee)):\(arguments.count)"
                }.joined(separator: ", ")
                let executeCall = try #require(probeBody.first { instruction in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                        return false
                    }
                    return interner.resolve(callee) == "kk_worker_execute" && arguments.count == 6
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

            // source 4: parameter mapping before prepending captures
            do {
                let mainBody = try findKIRFunctionBody(named: "main4", in: module, interner: interner)
                let lambdaCall = try #require(mainBody.first { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                        return false
                    }
                    return interner.resolve(callee).hasPrefix("kk_function_value_adapter_")
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

            // source 6: callable reference lowers to callable symbol value
            do {
                let incSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .function && interner.resolve(symbol.name) == "inc6"
                })?.id)

                let mainBody = try findKIRFunctionBody(named: "main6", in: module, interner: interner)
                let incCall = try #require(mainBody.first { instruction in
                    guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else {
                        return false
                    }
                    return symbol == incSymbol
                })

                guard case let .call(callSymbol, callee, arguments, _, _, _, _, _) = incCall else {
                    Issue.record("Expected callable reference call to inc6.")
                    return
                }
                #expect(callSymbol == incSymbol)
                #expect(interner.resolve(callee) == "inc6")
                #expect(arguments.count == 1)
                guard case .intLiteral(2)? = module.arena.expr(arguments[0]) else {
                    Issue.record("Expected callable reference call to forward the explicit argument.")
                    return
                }
            }

            // source 7: bound callable reference receiver as capture argument
            do {
                let plusSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .function && interner.resolve(symbol.name) == "plus7"
                })?.id)

                let mainBody = try findKIRFunctionBody(named: "main7", in: module, interner: interner)
                let plusCall = try #require(mainBody.first { instruction in
                    guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else {
                        return false
                    }
                    return symbol == plusSymbol || interner.resolve(callee) == "plus7"
                })

                guard case let .call(_, callee, arguments, _, _, _, _, _) = plusCall else {
                    Issue.record("Expected bound callable reference to lower to plus7 call.")
                    return
                }
                #expect(interner.resolve(callee) == "plus7")
                #expect(arguments.count == 2)
                guard case let .symbolRef(receiverSymbol)? = module.arena.expr(arguments[0]),
                      let receiver = sema.symbols.symbol(receiverSymbol)
                else {
                    Issue.record("Expected first argument to be captured receiver symbol.")
                    return
                }
                #expect(interner.resolve(receiver.name) == "box")
                guard case .intLiteral(7)? = module.arena.expr(arguments[1]) else {
                    Issue.record("Expected second argument to be call-site argument.")
                    return
                }
            }
        }
    }

    @Test func testBuildKIRNestedEscapingFunctionTypeComparesArithmeticBeforeReturn() throws {
        let source = """
        package sample5

        fun main5() {
            val f: (Int) -> (String) -> Boolean = { m -> { s -> s.length * m > 10 } }
            println(f(2)("hello"))
            println(f(2)("hi"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NestedLambdaLowering", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner
            let innerLambda = try #require(findAllKIRFunctions(in: module).first { function in
                guard interner.resolve(function.name).hasPrefix("kk_lambda_") else {
                    return false
                }
                let callNames = extractCallees(from: function.body, interner: interner)
                return callNames.contains("kk_op_mul") && callNames.contains("kk_op_gt")
            })
            let innerCallNames = extractCallees(from: innerLambda.body, interner: interner)
            #expect(innerCallNames.contains("__string_struct_get_length"))
            #expect(innerCallNames.contains("kk_op_mul"))
            #expect(innerCallNames.contains("kk_op_gt"))

            let adapterFunction = try #require(findAllKIRFunctions(in: module).first { function in
                interner.resolve(function.name).hasPrefix("kk_function_value_adapter_")
            })
            let adapterCallNames = extractCallees(from: adapterFunction.body, interner: interner)
            #expect(
                adapterCallNames.contains { name in
                    name.hasPrefix("kk_closure_invoke_") || name.hasPrefix("kk_lambda_")
                }
            )
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
}
#endif
