#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
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

    @Test func testBuildKIRLowersExpressionsAndMemberOperators() throws {
        let sources = [
            """
            package sample0
            fun main0() = "a" + "b"
            """,
            """
            package sample1
            fun lengthOf1(value: String): Int {
                return value.length
            }
            """,
            """
            package sample2
            fun parse2(value: String): Int = value.toInt()
            fun trimValue2(value: String): String = value.trim()
            fun takeTwo2(value: String): String = value.take(2)
            """,
            """
            package sample3
            fun String.implicitOneArg3(n: Int): String = substring(n)
            fun String.implicitTwoArgs3(a: Int, b: Int): String = substring(a, b)
            fun String.explicitOneArg3(n: Int): String = this.substring(n)
            """,
            """
            package sample4
            fun main4(): Int {
                val x = 2
                val a = -x
                val b = +x
                if (!false) return a + b
                return 0
            }
            """,
            """
            package sample5
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
            package sample6
            fun main6() {
                val f = true && false
                val g = false || true
                println(f)
                println(g)
            }
            """,
            """
            package sample7
            operator fun Int.plus(other: Int): Int = this - other
            fun main7(): Int = 7 + 3
            """,
            """
            package sample8
            class Vec8 {
                operator fun plus(other: Vec8): Vec8 = this
            }
            fun useOperator8(a: Vec8, b: Vec8): Vec8 = a + b
            """,
            """
            package sample9
            class Vec9 {
                fun plus(other: Vec9): Vec9 = this
            }
            fun useMemberCall9(a: Vec9, b: Vec9): Vec9 = a.plus(b)
            """,
            """
            package sample10
            class Vec10 {
                operator fun unaryMinus(): Vec10 = this
            }
            fun useUnary10(a: Vec10): Vec10 = -a
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)

            // sample0: string concat
            do {
                let body = try findKIRFunctionBody(named: "main0", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)

                #expect(callees.contains("kk_string_concat_flat"))
                #expect(!(body.contains { instruction in
                    guard case let .binary(op, _, _, _) = instruction else { return false }
                    return op == .add
                }))
            }

            // sample1: string length
            do {
                let body = try findKIRFunctionBody(named: "lengthOf1", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)

                #expect(callees.contains("__string_struct_get_length"))
                #expect(!callees.contains("kk_string_struct_get_length"))
            }

            // sample2: table-driven string members
            do {
                let parseCallees = Set(extractCallees(
                    from: try findKIRFunctionBody(named: "parse2", in: module, interner: interner),
                    interner: interner
                ))
                let trimCallees = Set(extractCallees(
                    from: try findKIRFunctionBody(named: "trimValue2", in: module, interner: interner),
                    interner: interner
                ))
                let takeCallees = Set(extractCallees(
                    from: try findKIRFunctionBody(named: "takeTwo2", in: module, interner: interner),
                    interner: interner
                ))

                #expect(parseCallees.contains("kk_string_toInt_flat"))
                #expect(trimCallees.contains("trim"))
                #expect(!trimCallees.contains("kk_string_trim_flat"))
                #expect(takeCallees.contains("take"))
                #expect(!takeCallees.contains("kk_string_take_flat"))
            }

            // sample3: implicit receiver substring
            do {
                let expectedArgumentCounts = [
                    "implicitOneArg3": 2,
                    "implicitTwoArgs3": 3,
                    "explicitOneArg3": 2,
                ]
                for (functionName, expectedArgumentCount) in expectedArgumentCounts {
                    let body = try findKIRFunctionBody(named: functionName, in: module, interner: interner)
                    #expect(!extractCallees(from: body, interner: interner).contains("kk_string_substring_flat"))

                    let substringCall = try #require(body.compactMap { instruction -> [KIRExprID]? in
                        guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                              interner.resolve(callee) == "substring"
                        else { return nil }
                        return arguments
                    }.first, "\(functionName) should lower to a source-backed substring call")

                    #expect(
                        substringCall.count == expectedArgumentCount,
                        "\(functionName) should pass \(expectedArgumentCount) arguments, got \(substringCall.count)"
                    )
                }
            }

            // sample4: unary operators
            do {
                let body = try findKIRFunctionBody(named: "main4", in: module, interner: interner)
                let binaryOps = body.compactMap { instruction -> KIRBinaryOp? in
                    guard case let .binary(op, _, _, _) = instruction else { return nil }
                    return op
                }
                #expect(binaryOps.contains(.subtract))
                #expect(binaryOps.contains(.equal))
            }

            // sample5: comparison operators
            do {
                let body = try findKIRFunctionBody(named: "main5", in: module, interner: interner)
                let callees = Set(extractCallees(from: body, interner: interner))

                #expect(callees.contains("kk_op_ne"))
                #expect(callees.contains("kk_op_lt"))
                #expect(callees.contains("kk_op_le"))
                #expect(callees.contains("kk_op_gt"))
                #expect(callees.contains("kk_op_ge"))
            }

            // sample6: logical operators
            do {
                let body = try findKIRFunctionBody(named: "main6", in: module, interner: interner)
                let callees = Set(extractCallees(from: body, interner: interner))

                #expect(!callees.contains("kk_op_and"))
                #expect(!callees.contains("kk_op_or"))
                let jumpIfEqualCount = body.count { instruction in
                    if case .jumpIfEqual = instruction { return true }
                    return false
                }
                #expect(jumpIfEqualCount >= 2)
            }

            // sample7: resolved operator overload (Int.plus extension must not shadow built-in)
            do {
                let body = try findKIRFunctionBody(named: "main7", in: module, interner: interner)

                #expect(body.contains { instruction in
                    guard case let .binary(op, _, _, _) = instruction else { return false }
                    return op == .add
                })
                #expect(!(body.contains { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return interner.resolve(callee) == "plus"
                }))
            }

            // sample8: member operator symbol for binary plus
            do {
                let operatorExprID = try #require(topLevelExpressionBodyExprID(
                    named: "useOperator8",
                    ast: ast,
                    interner: interner
                ))
                guard let operatorExpr = ast.arena.expr(operatorExprID),
                      case let .binary(op, _, _, _) = operatorExpr
                else {
                    Issue.record("Expected useOperator8 body to be a binary expression.")
                    return
                }
                #expect(op == .add)
                let resolvedBinding = try #require(sema.bindings.callBindings[operatorExprID])
                let chosenSymbol = resolvedBinding.chosenCallee
                let chosenSemanticSymbol = try #require(sema.symbols.symbol(chosenSymbol))
                #expect(interner.resolve(chosenSemanticSymbol.name) == "plus")
                let ownerSymbolID = try #require(sema.symbols.parentSymbol(for: chosenSymbol))
                let ownerSymbol = try #require(sema.symbols.symbol(ownerSymbolID))
                #expect(interner.resolve(ownerSymbol.name) == "Vec8")
                let signature = try #require(sema.symbols.functionSignature(for: chosenSymbol))
                #expect(signature.receiverType != nil)
                #expect(sema.bindings.exprTypes[operatorExprID] == signature.returnType)

                let body = try findKIRFunctionBody(named: "useOperator8", in: module, interner: interner)
                let resolvedCall = try #require(body.first { instruction in
                    guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                    return symbol == chosenSymbol
                })
                guard case let .call(callSymbol, callee, arguments, _, _, _, _, _) = resolvedCall else {
                    Issue.record("Expected chosen call instruction for useOperator8.")
                    return
                }

                #expect(callSymbol == chosenSymbol)
                #expect(interner.resolve(callee) == "plus")
                #expect(!(interner.resolve(callee).hasPrefix("kk_op_")))
                #expect(!(body.contains { instruction in
                    guard case let .binary(op, _, _, _) = instruction else { return false }
                    return op == .add
                }))
                #expect(!(body.contains { instruction in
                    guard case let .call(_, callCallee, _, _, _, _, _, _) = instruction else { return false }
                    return interner.resolve(callCallee).hasPrefix("kk_op_")
                }))
                #expect(symbolNames(for: arguments, module: module, sema: sema, interner: interner) == ["a", "b"])
            }

            // sample9: explicit member call by inserting receiver argument
            do {
                let memberExprID = try #require(topLevelExpressionBodyExprID(
                    named: "useMemberCall9",
                    ast: ast,
                    interner: interner
                ))
                guard let memberExpr = ast.arena.expr(memberExprID),
                      case .memberCall = memberExpr
                else {
                    Issue.record("Expected useMemberCall9 body to be a member call expression.")
                    return
                }
                let resolvedBinding = try #require(sema.bindings.callBindings[memberExprID])
                let chosenSymbol = resolvedBinding.chosenCallee
                let chosenSemanticSymbol = try #require(sema.symbols.symbol(chosenSymbol))
                #expect(interner.resolve(chosenSemanticSymbol.name) == "plus")
                let ownerSymbolID = try #require(sema.symbols.parentSymbol(for: chosenSymbol))
                let ownerSymbol = try #require(sema.symbols.symbol(ownerSymbolID))
                #expect(interner.resolve(ownerSymbol.name) == "Vec9")
                let signature = try #require(sema.symbols.functionSignature(for: chosenSymbol))
                #expect(signature.receiverType != nil)
                #expect(sema.bindings.exprTypes[memberExprID] == signature.returnType)

                let body = try findKIRFunctionBody(named: "useMemberCall9", in: module, interner: interner)
                let memberCall = try #require(body.first { instruction in
                    guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                    return symbol == chosenSymbol
                })
                guard case let .call(callSymbol, callee, arguments, _, _, _, _, _) = memberCall else {
                    Issue.record("Expected chosen call instruction for useMemberCall9.")
                    return
                }

                #expect(callSymbol == chosenSymbol)
                #expect(interner.resolve(callee) == "plus")
                #expect(symbolNames(for: arguments, module: module, sema: sema, interner: interner) == ["a", "b"])
            }

            // sample10: chosen unary operator symbol for unary minus
            do {
                let operatorExprID = try #require(topLevelExpressionBodyExprID(
                    named: "useUnary10",
                    ast: ast,
                    interner: interner
                ))
                guard let operatorExpr = ast.arena.expr(operatorExprID),
                      case let .unaryExpr(op, _, _) = operatorExpr
                else {
                    Issue.record("Expected useUnary10 body to be a unary expression.")
                    return
                }
                #expect(op == .unaryMinus)
                let resolvedBinding = try #require(sema.bindings.callBindings[operatorExprID])
                let chosenSymbol = resolvedBinding.chosenCallee
                let chosenSemanticSymbol = try #require(sema.symbols.symbol(chosenSymbol))
                #expect(interner.resolve(chosenSemanticSymbol.name) == "unaryMinus")
                let ownerSymbolID = try #require(sema.symbols.parentSymbol(for: chosenSymbol))
                let ownerSymbol = try #require(sema.symbols.symbol(ownerSymbolID))
                #expect(interner.resolve(ownerSymbol.name) == "Vec10")
                let signature = try #require(sema.symbols.functionSignature(for: chosenSymbol))
                #expect(signature.receiverType != nil)
                #expect(sema.bindings.exprTypes[operatorExprID] == signature.returnType)

                let body = try findKIRFunctionBody(named: "useUnary10", in: module, interner: interner)
                let resolvedCall = try #require(body.first { instruction in
                    guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                    return symbol == chosenSymbol
                })
                guard case let .call(callSymbol, callee, arguments, _, _, _, _, _) = resolvedCall else {
                    Issue.record("Expected chosen call instruction for useUnary10.")
                    return
                }

                #expect(callSymbol == chosenSymbol)
                #expect(interner.resolve(callee) == "unaryMinus")
                #expect(symbolNames(for: arguments, module: module, sema: sema, interner: interner) == ["a"])
                #expect(!(body.contains { instruction in
                    guard case let .binary(op, _, _, _) = instruction else { return false }
                    return op == .subtract
                }))
            }
        }
    }

    // `val x: Any = 42L` must box the literal so its runtime representation
    // carries Long type info. Before the fix, a local decl's "declared type"
    // was taken from the initializer's own arena type (Long) instead of the
    // symbol's Sema-recorded declared type (Any), so the local aliased the
    // raw unboxed literal register and no box call was ever emitted.
    // Companion: an unannotated local (`val x = 42L`) must NOT gain a spurious
    // box/copy. The same widening gap also affected reassignment of a widened
    // local, so verify both the initial box and the reassignment's box.
    @Test func testLocalDeclBoxesWidenedLiteralsCorrectly() throws {
        let sources = [
            """
            package sample0
            fun main0() {
                val x: Any = 42L
                println(x)
            }
            """,
            """
            package sample1
            fun main1() {
                val x = 42L
                println(x)
            }
            """,
            """
            package sample2
            fun main2() {
                var v: Any = 42
                v = 100L
                println(v)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let body = try findKIRFunctionBody(named: "main0", in: module, interner: interner)
                let callees = Set(extractCallees(from: body, interner: interner))
                #expect(callees.contains("kk_box_long_nonnull"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main1", in: module, interner: interner)
                let callees = Set(extractCallees(from: body, interner: interner))
                #expect(!callees.contains("kk_box_long"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main2", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_box_int"))
                #expect(callees.contains("kk_box_long_nonnull"))
            }
        }
    }

    func topLevelExpressionBodyExprID(
        named functionName: String,
        ast: ASTModule,
        interner: StringInterner
    ) -> ExprID? {
        ast.files
            .flatMap(\.topLevelDecls)
            .compactMap { declID -> ExprID? in
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(funDecl) = decl,
                      interner.resolve(funDecl.name) == functionName,
                      case let .expr(exprID, _) = funDecl.body
                else {
                    return nil
                }
                return exprID
            }
            .first
    }

    func symbolNames(
        for arguments: [KIRExprID],
        module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        arguments.compactMap { argument in
            guard case let .symbolRef(symbolID)? = module.arena.expr(argument),
                  let symbol = sema.symbols.symbol(symbolID)
            else {
                return nil
            }
            return interner.resolve(symbol.name)
        }
    }
}
#endif
