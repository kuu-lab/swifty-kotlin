#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite @MainActor
struct BuildKIRRegressionTests {
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
                "StdlibDelegateLowering",
                "JvmStaticLowering",
                "JvmOverloadsLowering",
                "DataEnumSealedSynthesis",
                "EnumEntriesLowering",
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
        let source = """
        fun main() = "a" + "b"
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_string_concat_flat"))
            #expect(!(body.contains { instruction in
                guard case let .binary(op, _, _, _) = instruction else {
                    return false
                }
                return op == .add
            }))
        }
    }

    @Test func testBuildKIRLowersStringLengthToInternalAggregateAccessor() throws {
        let source = """
        fun lengthOf(value: String): Int {
            return value.length
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "lengthOf", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("__string_struct_get_length"))
            #expect(!callees.contains("kk_string_struct_get_length"))
        }
    }

    @Test func testBuildKIRLowersTableDrivenStringMembersToRuntimeOrSourceCalls() throws {
        let source = """
        fun parse(value: String): Int = value.toInt()
        fun trimValue(value: String): String = value.trim()
        fun takeTwo(value: String): String = value.take(2)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let parseCallees = Set(extractCallees(
                from: try findKIRFunctionBody(named: "parse", in: module, interner: ctx.interner),
                interner: ctx.interner
            ))
            let trimCallees = Set(extractCallees(
                from: try findKIRFunctionBody(named: "trimValue", in: module, interner: ctx.interner),
                interner: ctx.interner
            ))
            let takeCallees = Set(extractCallees(
                from: try findKIRFunctionBody(named: "takeTwo", in: module, interner: ctx.interner),
                interner: ctx.interner
            ))

            #expect(parseCallees.contains("kk_string_toInt_flat"))
            // String.trim is source-backed after the KSP-403 migration.
            #expect(trimCallees.contains("trim"))
            #expect(!trimCallees.contains("kk_string_trim_flat"))
            #expect(takeCallees.contains("kk_string_take_flat"))
        }
    }

    @Test func testBuildKIRLowersUnaryOperatorsToExpectedOperations() throws {
        let source = """
        fun main(): Int {
            val x = 2
            val a = -x
            val b = +x
            if (!false) return a + b
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let binaryOps = body.compactMap { instruction -> KIRBinaryOp? in
                guard case let .binary(op, _, _, _) = instruction else {
                    return nil
                }
                return op
            }
            #expect(binaryOps.contains(.subtract))
            #expect(binaryOps.contains(.equal))
        }
    }

    @Test func testBuildKIRLowersComparisonOperatorsToRuntimeCalls() throws {
        let source = """
        fun main(): Int {
            val x = 3
            val a = x != 2
            val b = x < 5
            val c = x <= 3
            val d = x > 1
            val e = x >= 3
            if (a && b && c && d && e) return 1
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: body, interner: ctx.interner))

            #expect(callees.contains("kk_op_ne"))
            #expect(callees.contains("kk_op_lt"))
            #expect(callees.contains("kk_op_le"))
            #expect(callees.contains("kk_op_gt"))
            #expect(callees.contains("kk_op_ge"))
        }
    }

    // `&&`/`||` must short-circuit, so they lower to conditional branches
    // (jumpIfEqual/label) rather than a runtime call that would evaluate both
    // operands unconditionally.
    @Test func testBuildKIRLowersLogicalOperatorsToShortCircuitBranches() throws {
        let source = """
        fun main() {
            val f = true && false
            val g = false || true
            println(f)
            println(g)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: body, interner: ctx.interner))

            #expect(!callees.contains("kk_op_and"))
            #expect(!callees.contains("kk_op_or"))
            let jumpIfEqualCount = body.count { instruction in
                if case .jumpIfEqual = instruction { return true }
                return false
            }
            #expect(jumpIfEqualCount >= 2)
        }
    }

    @Test func testBuildKIRUsesResolvedOperatorOverloadCallForBinaryExpression() throws {
        // Kotlin member functions take precedence over extensions with the same
        // signature.  Int.plus is a built-in member, so `operator fun Int.plus`
        // defined as an extension must NOT shadow the built-in `+`.
        let source = """
        operator fun Int.plus(other: Int): Int = this - other
        fun main(): Int = 7 + 3
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            // The built-in binary .add instruction should be used, not a call.
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
    }

    // MARK: - Member operator/member call integration (P5-19)

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
        let source = """
        fun main() {
            val x: Any = 42L
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: body, interner: ctx.interner))

            #expect(callees.contains("kk_box_long"))
        }
    }

    // Companion to the above: an unannotated local (`val x = 42L`) must NOT
    // gain a spurious box/copy — the declared and initializer types coincide,
    // so the direct-alias fast path should still apply.
    @Test func testLocalDeclDoesNotBoxWhenDeclaredTypeMatchesInitializer() throws {
        let source = """
        fun main() {
            val x = 42L
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: body, interner: ctx.interner))

            #expect(!callees.contains("kk_box_long"))
        }
    }

    // The same widening gap affected reassignment of a widened local: since
    // the *first* declaration never established an Any-typed storage slot,
    // later `v = <primitive>` copies inherited the initializer's narrow type
    // and skipped boxing too. Verify both the initial box and the
    // reassignment's box are now emitted.
    @Test func testLocalDeclWideningFixAlsoBoxesLaterReassignment() throws {
        let source = """
        fun main() {
            var v: Any = 42
            v = 100L
            println(v)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_box_int"))
            #expect(callees.contains("kk_box_long"))
        }
    }

}
#endif
