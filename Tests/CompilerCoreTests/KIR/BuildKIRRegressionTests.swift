#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct BuildKIRRegressionTests {

    private static nonisolated(unsafe) var _sharedBuildKIRCtx: CompilationContext?
    private static nonisolated(unsafe) var _sharedBuildKIRLoweredCtx: CompilationContext?

    private func sharedBuildKIRCtx() throws -> CompilationContext {
        if let cached = Self._sharedBuildKIRCtx {
            return cached
        }

        let sources: [String] = [
            """
            package buildkir.raw0
            fun main0() = "a" + "b"
            """,
            """
            package buildkir.raw1
            fun lengthOf1(value: String): Int {
                return value.length
            }
            """,
            """
            package buildkir.raw2
            fun parse2(value: String): Int = value.toInt()
            fun trimValue2(value: String): String = value.trim()
            fun takeTwo2(value: String): String = value.take(2)
            """,
            """
            package buildkir.raw3
            fun String.implicitOneArg3(n: Int): String = substring(n)
            fun String.implicitTwoArgs3(a: Int, b: Int): String = substring(a, b)
            fun String.explicitOneArg3(n: Int): String = this.substring(n)
            """,
            """
            package buildkir.raw4
            fun main4(): Int {
                val x = 2
                val a = -x
                val b = +x
                if (!false) return a + b
                return 0
            }
            """,
            """
            package buildkir.raw5
            fun main5(): Int {
                val x = 3
                val a = x != 2
                val b = x < 5
                val c = x <= 3
                val d = x > 1
                val e = x >= 3
                if (a && b && c && d && e) return 1
                return 0
            }
            """,
            """
            package buildkir.raw6
            fun main6() {
                val f = true && false
                val g = false || true
                println(f)
                println(g)
            }
            """,
            """
            package buildkir.raw7
            operator fun Int.plus(other: Int): Int = this - other
            fun main7(): Int = 7 + 3
            """,
        ]

        var result: CompilationContext?
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            result = ctx
        }

        let ctx = try #require(result)
        Self._sharedBuildKIRCtx = ctx
        return ctx
    }

    private func sharedBuildKIRLoweredCtx() throws -> CompilationContext {
        if let cached = Self._sharedBuildKIRLoweredCtx {
            return cached
        }

        let sources: [String] = [
            """
            package buildkir.lower0
            fun mainLower0() {
                val x: Any = 42L
                println(x)
            }
            """,
            """
            package buildkir.lower1
            fun mainLower1() {
                val x = 42L
                println(x)
            }
            """,
            """
            package buildkir.lower2
            fun mainLower2() {
                var v: Any = 42
                v = 100L
                println(v)
            }
            """,
        ]

        var result: CompilationContext?
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            result = ctx
        }

        let ctx = try #require(result)
        Self._sharedBuildKIRLoweredCtx = ctx
        return ctx
    }
    @Test func testLoadSourcesPhaseReportsMissingInputsAndUnreadableFiles() {
        let emptyCtx = makeCompilationContext(inputs: [])
        #expect(throws: (any Error).self) { try LoadSourcesPhase().run(emptyCtx) }
        #expect(emptyCtx.diagnostics.diagnostics.last?.code == "KSWIFTK-SOURCE-0001")

        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kt")
            .path
        let missingCtx = makeCompilationContext(inputs: [missingPath])
        #expect(throws: (any Error).self) { try LoadSourcesPhase().run(missingCtx) }
        #expect(missingCtx.diagnostics.diagnostics.last?.code == "KSWIFTK-SOURCE-0002")
    }

    @Test func testRunToKIRAndLoweringRecordsAllPasses() throws {
        let source = """
        inline fun add(a: Int, b: Int) = a + b
        suspend fun susp(v: Int) = v
        fun chooser(flag: Boolean, n: Int) = when (flag) { true -> n + 1, false -> n - 1, else -> n }
        fun main() {
            add(1, 2)
            susp(3)
            chooser(true, 4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            #expect(module.executedLowerings == [
                "TailrecLowering",
                "NormalizeBlocks",
                "OperatorLowering",
                "ForLowering",
                "CollectionLiteralLowering",
                "FlowLowering",
                "ValueClassUnboxing",
                "PropertyLowering",
                "JvmStaticLowering",
                "JvmOverloadsLowering",
                "DataEnumSealedSynthesis",
                "EnumEntriesLowering",
                "ConsolePrintLowering",
                "EnumNameAccessLowering",
                "LambdaClosureConversion",
                "InlineLowering",
                "CoroutineLowering",
                "IntegerNarrowing",
                "ABILowering",
            ])
            // Source defines add, susp, chooser, main
            #expect(module.functionCount >= 4)
        }
    }

    @Test func testBuildKIRLowersStringAdditionToRuntimeConcatCall() throws {
        let ctx = try sharedBuildKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main0", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("kk_string_concat_flat"))
        #expect(!(body.contains { instruction in
            guard case let .binary(op, _, _, _) = instruction else {
                return false
            }
            return op == .add
        }))
    }
    @Test func testBuildKIRLowersStringLengthToInternalAggregateAccessor() throws {
        let ctx = try sharedBuildKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "lengthOf1", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("__kk_string_struct_get_length"))
        #expect(!callees.contains("kk_string_struct_get_length"))
    }
    @Test func testBuildKIRLowersTableDrivenStringMembersToRuntimeOrSourceCalls() throws {
        let ctx = try sharedBuildKIRCtx()
        let module = try #require(ctx.kir)
        let parseCallees = Set(extractCallees(
            from: try findKIRFunctionBody(named: "parse2", in: module, interner: ctx.interner),
            interner: ctx.interner
        ))
        let trimCallees = Set(extractCallees(
            from: try findKIRFunctionBody(named: "trimValue2", in: module, interner: ctx.interner),
            interner: ctx.interner
        ))
        let takeCallees = Set(extractCallees(
            from: try findKIRFunctionBody(named: "takeTwo2", in: module, interner: ctx.interner),
            interner: ctx.interner
        ))

        #expect(parseCallees.contains("toInt"))
        #expect(!parseCallees.contains("kk_string_toInt_flat"))
        #expect(trimCallees.contains("trim"))
        #expect(!trimCallees.contains("kk_string_trim_flat"))
        #expect(takeCallees.contains("take"))
        #expect(!takeCallees.contains("kk_string_take_flat"))
    }
    @Test func testBuildKIRLowersImplicitReceiverSubstringWithReceiverArgument() throws {
        let ctx = try sharedBuildKIRCtx()
        let module = try #require(ctx.kir)
        let expectedArgumentCounts = [
            "implicitOneArg3": 2,
            "implicitTwoArgs3": 3,
            "explicitOneArg3": 2,
        ]
        for (functionName, expectedArgumentCount) in expectedArgumentCounts {
            let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
            #expect(!extractCallees(from: body, interner: ctx.interner).contains("kk_string_substring_flat"))

            let substringCall = try #require(body.compactMap { instruction -> [KIRExprID]? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == "substring"
                else {
                    return nil
                }
                return arguments
            }.first, "\(functionName) should lower to a source-backed substring call")

            #expect(
                substringCall.count == expectedArgumentCount,
                "\(functionName) should pass \(expectedArgumentCount) arguments, got \(substringCall.count)"
            )
        }
    }
    @Test func testBuildKIRLowersUnaryOperatorsToExpectedOperations() throws {
        let ctx = try sharedBuildKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main4", in: module, interner: ctx.interner)

        let binaryOps = body.compactMap { instruction -> KIRBinaryOp? in
            guard case let .binary(op, _, _, _) = instruction else {
                return nil
            }
            return op
        }
        #expect(binaryOps.contains(.subtract))
        #expect(binaryOps.contains(.equal))
    }
    @Test func testBuildKIRLowersComparisonOperatorsToRuntimeCalls() throws {
        let ctx = try sharedBuildKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main5", in: module, interner: ctx.interner)
        let callees = Set(extractCallees(from: body, interner: ctx.interner))

        #expect(callees.contains("kk_op_ne"))
        #expect(callees.contains("kk_op_lt"))
        #expect(callees.contains("kk_op_le"))
        #expect(callees.contains("kk_op_gt"))
        #expect(callees.contains("kk_op_ge"))
    }
    @Test func testBuildKIRLowersLogicalOperatorsToShortCircuitBranches() throws {
        let ctx = try sharedBuildKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main6", in: module, interner: ctx.interner)
        let callees = Set(extractCallees(from: body, interner: ctx.interner))

        #expect(!callees.contains("kk_op_and"))
        #expect(!callees.contains("kk_op_or"))
        let jumpIfEqualCount = body.count { instruction in
            if case .jumpIfEqual = instruction { return true }
            return false
        }
        #expect(jumpIfEqualCount >= 2)
    }
    @Test func testBuildKIRUsesResolvedOperatorOverloadCallForBinaryExpression() throws {
        let ctx = try sharedBuildKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main7", in: module, interner: ctx.interner)

        #expect(body.contains { instruction in
            guard case let .binary(op, _, _, _) = instruction else {
                return false
            }
            return op == .add
        })
        #expect(!(body.contains { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                return false
            }
            return ctx.interner.resolve(callee) == "plus"
        }))
    }
    @Test func testBuildKIRUsesChosenMemberOperatorSymbolForBinaryPlusExpression() throws {
        let source = """
        class Vec {
            operator fun plus(other: Vec): Vec = this
        }
        fun useOperator(a: Vec, b: Vec): Vec = a + b
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)

            let operatorExprID = try #require(topLevelExpressionBodyExprID(
                named: "useOperator",
                ast: ast,
                interner: ctx.interner
            ))
            guard let operatorExpr = ast.arena.expr(operatorExprID),
                  case let .binary(op, _, _, _) = operatorExpr
            else {
                Issue.record("Expected useOperator body to be a binary expression.")
                return
            }
            #expect(op == .add)
            let resolvedBinding = try #require(sema.bindings.callBindings[operatorExprID])
            let chosenSymbol = resolvedBinding.chosenCallee
            let chosenSemanticSymbol = try #require(sema.symbols.symbol(chosenSymbol))
            #expect(ctx.interner.resolve(chosenSemanticSymbol.name) == "plus")
            let ownerSymbolID = try #require(sema.symbols.parentSymbol(for: chosenSymbol))
            let ownerSymbol = try #require(sema.symbols.symbol(ownerSymbolID))
            #expect(ctx.interner.resolve(ownerSymbol.name) == "Vec")
            let signature = try #require(sema.symbols.functionSignature(for: chosenSymbol))
            #expect(signature.receiverType != nil)
            #expect(sema.bindings.exprTypes[operatorExprID] == signature.returnType)

            try BuildKIRPhase().run(ctx)

            let module = try #require(ctx.kir)

            let body = try findKIRFunctionBody(named: "useOperator", in: module, interner: ctx.interner)
            let resolvedCall = try #require(body.first { instruction in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == chosenSymbol
            })
            guard case let .call(callSymbol, callee, arguments, _, _, _, _, _) = resolvedCall else {
                Issue.record("Expected chosen call instruction for useOperator.")
                return
            }

            #expect(callSymbol == chosenSymbol)
            #expect(ctx.interner.resolve(callee) == "plus")
            #expect(!(ctx.interner.resolve(callee).hasPrefix("kk_op_")))
            #expect(!(body.contains { instruction in
                guard case let .binary(op, _, _, _) = instruction else {
                    return false
                }
                return op == .add
            }))
            #expect(!(body.contains { instruction in
                guard case let .call(_, callCallee, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callCallee).hasPrefix("kk_op_")
            }))
            #expect(symbolNames(for: arguments, module: module, sema: sema, interner: ctx.interner) == ["a", "b"])
        }
    }

    @Test func testBuildKIRLowersExplicitMemberCallByInsertingReceiverArgument() throws {
        let source = """
        class Vec {
            fun plus(other: Vec): Vec = this
        }
        fun useMemberCall(a: Vec, b: Vec): Vec = a.plus(b)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)

            let memberExprID = try #require(topLevelExpressionBodyExprID(
                named: "useMemberCall",
                ast: ast,
                interner: ctx.interner
            ))
            guard let memberExpr = ast.arena.expr(memberExprID),
                  case .memberCall = memberExpr
            else {
                Issue.record("Expected useMemberCall body to be a member call expression.")
                return
            }
            let resolvedBinding = try #require(sema.bindings.callBindings[memberExprID])
            let chosenSymbol = resolvedBinding.chosenCallee
            let chosenSemanticSymbol = try #require(sema.symbols.symbol(chosenSymbol))
            #expect(ctx.interner.resolve(chosenSemanticSymbol.name) == "plus")
            let ownerSymbolID = try #require(sema.symbols.parentSymbol(for: chosenSymbol))
            let ownerSymbol = try #require(sema.symbols.symbol(ownerSymbolID))
            #expect(ctx.interner.resolve(ownerSymbol.name) == "Vec")
            let signature = try #require(sema.symbols.functionSignature(for: chosenSymbol))
            #expect(signature.receiverType != nil)
            #expect(sema.bindings.exprTypes[memberExprID] == signature.returnType)

            try BuildKIRPhase().run(ctx)

            let module = try #require(ctx.kir)

            let body = try findKIRFunctionBody(named: "useMemberCall", in: module, interner: ctx.interner)
            let memberCall = try #require(body.first { instruction in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == chosenSymbol
            })
            guard case let .call(callSymbol, callee, arguments, _, _, _, _, _) = memberCall else {
                Issue.record("Expected chosen call instruction for useMemberCall.")
                return
            }

            #expect(callSymbol == chosenSymbol)
            #expect(ctx.interner.resolve(callee) == "plus")
            #expect(symbolNames(for: arguments, module: module, sema: sema, interner: ctx.interner) == ["a", "b"])
        }
    }

    @Test func testBuildKIRUsesChosenUnaryOperatorSymbolForUnaryMinusExpression() throws {
        let source = """
        class Vec {
            operator fun unaryMinus(): Vec = this
        }
        fun useUnary(a: Vec): Vec = -a
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)

            let operatorExprID = try #require(topLevelExpressionBodyExprID(
                named: "useUnary",
                ast: ast,
                interner: ctx.interner
            ))
            guard let operatorExpr = ast.arena.expr(operatorExprID),
                  case let .unaryExpr(op, _, _) = operatorExpr
            else {
                Issue.record("Expected useUnary body to be a unary expression.")
                return
            }
            #expect(op == .unaryMinus)
            let resolvedBinding = try #require(sema.bindings.callBindings[operatorExprID])
            let chosenSymbol = resolvedBinding.chosenCallee
            let chosenSemanticSymbol = try #require(sema.symbols.symbol(chosenSymbol))
            #expect(ctx.interner.resolve(chosenSemanticSymbol.name) == "unaryMinus")
            let ownerSymbolID = try #require(sema.symbols.parentSymbol(for: chosenSymbol))
            let ownerSymbol = try #require(sema.symbols.symbol(ownerSymbolID))
            #expect(ctx.interner.resolve(ownerSymbol.name) == "Vec")
            let signature = try #require(sema.symbols.functionSignature(for: chosenSymbol))
            #expect(signature.receiverType != nil)
            #expect(sema.bindings.exprTypes[operatorExprID] == signature.returnType)

            try BuildKIRPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "useUnary", in: module, interner: ctx.interner)
            let resolvedCall = try #require(body.first { instruction in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == chosenSymbol
            })
            guard case let .call(callSymbol, callee, arguments, _, _, _, _, _) = resolvedCall else {
                Issue.record("Expected chosen call instruction for useUnary.")
                return
            }

            #expect(callSymbol == chosenSymbol)
            #expect(ctx.interner.resolve(callee) == "unaryMinus")
            #expect(symbolNames(for: arguments, module: module, sema: sema, interner: ctx.interner) == ["a"])
            #expect(!(body.contains { instruction in
                guard case let .binary(op, _, _, _) = instruction else {
                    return false
                }
                return op == .subtract
            }))
        }
    }

    // `val x: Any = 42L` must box the literal so its runtime representation
    // carries Long type info. Before the fix, a local decl's "declared type"
    // was taken from the initializer's own arena type (Long) instead of the
    // symbol's Sema-recorded declared type (Any), so the local aliased the
    // raw unboxed literal register and no box call was ever emitted.
    @Test func testLocalDeclBoxesLiteralWhenWidenedToAny() throws {
        let ctx = try sharedBuildKIRLoweredCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "mainLower0", in: module, interner: ctx.interner)
        let callees = Set(extractCallees(from: body, interner: ctx.interner))

        #expect(callees.contains("kk_box_long_nonnull"))
    }
    @Test func testLocalDeclDoesNotBoxWhenDeclaredTypeMatchesInitializer() throws {
        let ctx = try sharedBuildKIRLoweredCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "mainLower1", in: module, interner: ctx.interner)
        let callees = Set(extractCallees(from: body, interner: ctx.interner))

        #expect(!callees.contains("kk_box_long"))
    }
    @Test func testLocalDeclWideningFixAlsoBoxesLaterReassignment() throws {
        let ctx = try sharedBuildKIRLoweredCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "mainLower2", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("kk_box_int"))
        #expect(callees.contains("kk_box_long_nonnull"))
    }
}
#endif
