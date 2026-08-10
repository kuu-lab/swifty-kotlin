#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testControlFlowAndObjectLiteralKIR() throws {
        let sources = [
            """
            fun sideEffect1(x: Int): Int = x
            fun test1(flag: Boolean): Int {
                if (flag) sideEffect1(1) else sideEffect1(2)
                return 0
            }
            """,
            """
            fun earlyReturn2(flag: Boolean): Int {
                val result = if (flag) return 42 else 0
                return result
            }
            """,
            """
            fun effect3(x: Int): Int = x
            fun test3(v: Int): Int = when (v) { 1 -> effect3(10), 2 -> effect3(20), else -> effect3(30) }
            """,
            """
            class MyErr4

            fun bodyCall4(x: Int): Int = x
            fun catchCall4(x: Int): Int = x + 1
            fun finallyCall4(): Int = 0

            fun demo4(v: Int): Int {
                return try {
                    bodyCall4(v)
                } catch (e: Int) {
                    catchCall4(e)
                } catch (e: MyErr4) {
                    7
                } finally {
                    finallyCall4()
                }
            }
            """,
            """
            class MyException5

            fun riskyCall5(): Int = 42

            fun demo5(): Int {
                return try {
                    riskyCall5()
                } catch (e: MyException5) {
                    -1
                }
            }
            """,
            """
            class ErrA6
            class ErrB6

            fun riskyCall6(): Int = 42

            fun demo6(): Int {
                return try {
                    riskyCall6()
                } catch (e: ErrA6) {
                    -1
                } catch (e: ErrB6) {
                    -2
                }
            }
            """,
            """
            fun riskyCall7(): Int = 42

            fun demo7(): Int {
                return try {
                    riskyCall7()
                } catch (e: Any) {
                    -1
                }
            }
            """,
            """
            interface Marker8
            fun make8(): Marker8 = object : Marker8 {}
            """,
            """
            fun main9(): Int {
                val instance = object {
                    val value: Int = 7
                }
                return instance.value
            }
            """,
            """
            fun main10(): Int {
                val instance = object {
                    val seed: Int = 7
                    val value: Int
                        get() = seed + 1
                }
                return instance.value
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let module = try #require(ctx.kir)

            // sample0: if-expression side effects do not leak from unselected branch
            do {
                let body = try findKIRFunctionBody(named: "test1", in: module, interner: ctx.interner)
                let sideEffectCalls = body.filter { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "sideEffect1"
                }
                #expect(sideEffectCalls.count == 2, "Both branches should have sideEffect1 calls in IR")

                let jumpIfEqualCount = body.filter { if case .jumpIfEqual = $0 { return true }; return false }.count
                #expect(jumpIfEqualCount >= 1, "Condition should guard branch entry via jumpIfEqual")
            }

            // sample1: if-expression return in unselected branch does not leak
            do {
                let body = try findKIRFunctionBody(named: "earlyReturn2", in: module, interner: ctx.interner)
                let labelCount = body.filter { if case .label = $0 { return true }; return false }.count
                #expect(labelCount >= 2, "return-in-branch needs labels for control flow")

                let hasReturnValue = body.contains { if case .returnValue = $0 { return true }; return false }
                #expect(hasReturnValue, "Branch with return 42 should emit returnValue")
            }

            // sample2: when-expression side effects do not leak from unselected branch
            do {
                let body = try findKIRFunctionBody(named: "test3", in: module, interner: ctx.interner)
                let effectCalls = body.filter { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "effect3"
                }
                #expect(effectCalls.count == 3, "All 3 branches should have effect3 calls in IR")

                let labelCount = body.filter { if case .label = $0 { return true }; return false }.count
                #expect(labelCount >= 3, "Each branch needs labels for control flow")
            }

            // sample3: try/catch/finally lowering uses ordered type dispatch and thrown-slot routing
            do {
                let sample4Path = paths[3]
                let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: sample4Path))
                let tryExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else {
                        return false
                    }
                    if case .tryExpr = expr { return true }
                    return false
                })
                guard case let .tryExpr(_, catchClauses, _, _)? = ast.arena.expr(tryExprID) else {
                    Issue.record("Expected try expression.")
                    return
                }
                guard catchClauses.count == 2 else {
                    Issue.record("Expected two catch clauses.")
                    return
                }

                let catchBindings = try catchClauses.map { clause in
                    try #require(sema.bindings.catchClauseBinding(for: clause.body))
                }
                #expect(catchBindings[0].parameterSymbol != .invalid)
                #expect(catchBindings[1].parameterSymbol != .invalid)

                let body = try findKIRFunctionBody(named: "demo4", in: module, interner: ctx.interner)
                let matcherCalls = body.compactMap { instruction -> KIRInstruction? in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "kk_catch_type_matches"
                    else {
                        return nil
                    }
                    _ = arguments
                    return instruction
                }
                #expect(matcherCalls.isEmpty, "Try-catch lowering should not require runtime matcher helper calls.")

                let labelPositions: [Int32: Int] = body.enumerated().reduce(into: [:]) { partial, entry in
                    if case let .label(labelID) = entry.element {
                        partial[labelID] = entry.offset
                    }
                }

                func thrownEdge(for calleeName: String) -> (callIndex: Int, thrownSlot: KIRExprID, typeSlot: KIRExprID, target: Int32)? {
                    guard let callIndex = body.firstIndex(where: { instruction in
                        guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                            return false
                        }
                        return ctx.interner.resolve(callee) == calleeName
                    }) else {
                        return nil
                    }
                    guard case let .call(_, _, _, _, _, thrownResult?, _, _) = body[callIndex] else {
                        return nil
                    }
                    let tokenConstIndex = callIndex + 1
                    let tokenCopyIndex = callIndex + 2
                    let jumpIndex = callIndex + 3
                    guard body.indices.contains(tokenConstIndex),
                          body.indices.contains(tokenCopyIndex),
                          body.indices.contains(jumpIndex),
                          case let .constValue(unknownTypeToken, .intLiteral(0)) = body[tokenConstIndex],
                          case .copy(from: unknownTypeToken, to: let typeSlot) = body[tokenCopyIndex],
                          case let .jumpIfNotNull(value, target) = body[jumpIndex],
                          value == thrownResult
                    else {
                        return nil
                    }
                    return (callIndex, thrownResult, typeSlot, target)
                }

                guard let bodyEdge = thrownEdge(for: "bodyCall4"),
                      let catchEdge = thrownEdge(for: "catchCall4"),
                      let finallyEdge = thrownEdge(for: "finallyCall4")
                else {
                    Issue.record("Expected throw-aware edges for body/catch/finally calls.")
                    return
                }

                #expect(bodyEdge.thrownSlot == catchEdge.thrownSlot)
                #expect(bodyEdge.typeSlot == catchEdge.typeSlot)
                #expect(bodyEdge.thrownSlot != finallyEdge.thrownSlot)
                #expect(bodyEdge.typeSlot != finallyEdge.typeSlot)
                let sharedExceptionTypeSlot = bodyEdge.typeSlot

                guard let bodyDispatchPos = labelPositions[bodyEdge.target],
                      let finallyEntryPos = labelPositions[catchEdge.target],
                      let rethrowPos = labelPositions[finallyEdge.target]
                else {
                    Issue.record("Expected target labels for body/catch/finally throw edges.")
                    return
                }
                #expect(bodyDispatchPos < finallyEntryPos, "Body exceptions should route to catch dispatch before finally.")
                #expect(finallyEntryPos < rethrowPos, "Finally exceptions should route directly to outer rethrow.")
                #expect(bodyEdge.target != catchEdge.target)
                #expect(catchEdge.target != finallyEdge.target)

                let typeComparisons = body.enumerated().compactMap { index, instruction -> (index: Int, typeToken: Int64)? in
                    guard case .binary(op: .equal, lhs: let lhs, rhs: let rhs, result: _) = instruction,
                          lhs == sharedExceptionTypeSlot,
                          case let .intLiteral(token)? = module.arena.expr(rhs)
                    else {
                        return nil
                    }
                    return (index, token)
                }
                let expectedTypeTokens = catchBindings.map { RuntimeTypeCheckToken.encode(type: $0.parameterType, sema: sema, interner: ctx.interner) }
                let exactTypeComparisons = typeComparisons.filter { $0.typeToken != 0 }
                let unknownTypeComparisons = typeComparisons.filter { $0.typeToken == 0 }
                #expect(exactTypeComparisons.count == expectedTypeTokens.count, "Expected one exact type comparison per catch clause.")
                #expect(exactTypeComparisons.map(\.typeToken) == expectedTypeTokens)
                #expect(unknownTypeComparisons.count == expectedTypeTokens.count, "Expected one unknown-token fallback comparison per catch clause.")
                guard exactTypeComparisons.count == expectedTypeTokens.count else {
                    return
                }

                let finallyGuardJump = body.enumerated().contains { index, instruction in
                    guard index >= finallyEdge.callIndex + 3,
                          case let .jumpIfNotNull(value, target) = instruction
                    else {
                        return false
                    }
                    return value == finallyEdge.thrownSlot && target == finallyEdge.target
                }
                #expect(finallyGuardJump, "Expected post-finally rethrow guard for pending exception slot.")
                #expect(body.contains { instruction in
                    if case let .rethrow(value) = instruction {
                        return value == finallyEdge.thrownSlot
                    }
                    return false
                })

                guard case let .call(_, _, catchArguments, _, _, _, _, _) = body[catchEdge.callIndex],
                      let firstCatchArgument = catchArguments.first
                else {
                    Issue.record("Expected catchCall4 argument in first catch body.")
                    return
                }
                #expect(module.arena.exprType(firstCatchArgument) == catchBindings[0].parameterType)
            }

            // sample4: UNKNOWN-token catch clause uses runtime type check
            do {
                let body = try findKIRFunctionBody(named: "demo5", in: module, interner: ctx.interner)
                let opIsCalls = body.filter { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "kk_op_is"
                }
                #expect(opIsCalls.count >= 1, "Expected at least one kk_op_is call for runtime type check fallback on UNKNOWN token.")

                let firstOpIsCall = try #require(opIsCalls.first)
                if case let .call(_, _, arguments, _, _, _, _, _) = firstOpIsCall {
                    #expect(arguments.count == 2, "kk_op_is should receive exception value and type token.")
                }

                let zeroSentinelIDs: [KIRExprID] = body.compactMap { instruction in
                    guard case let .constValue(result, value) = instruction,
                          value == .intLiteral(0) else { return nil }
                    return result
                }
                #expect(zeroSentinelIDs.count >= 1, "Expected at least one constValue(0) for the UNKNOWN-token sentinel.")

                let zeroCompareExists = body.contains { instruction in
                    guard case let .binary(op, _, rhs, _) = instruction,
                          op == .equal else { return false }
                    return zeroSentinelIDs.contains(rhs)
                }
                #expect(zeroCompareExists, "Expected a binary(.equal) comparing exceptionTypeSlot against the zero sentinel constValue(0).")
            }

            // sample5: multiple UNKNOWN-token catch clauses use runtime type check
            do {
                let body = try findKIRFunctionBody(named: "demo6", in: module, interner: ctx.interner)
                let opIsCalls = body.filter { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "kk_op_is"
                }
                #expect(opIsCalls.count >= 2, "Expected at least one kk_op_is call per typed catch clause for runtime type check fallback.")
            }

            // sample6: catch-all (Any) does not emit runtime type check
            do {
                let body = try findKIRFunctionBody(named: "demo7", in: module, interner: ctx.interner)
                let opIsCalls = body.filter { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "kk_op_is"
                }
                #expect(opIsCalls.count == 0, "catch-all (Any) should not emit kk_op_is runtime type check.")
            }

            // sample7: object literal lowers to generated factory returning runtime object entity
            do {
                let makeExprID = try #require(topLevelExpressionBodyExprID(
                    named: "make8",
                    ast: ast,
                    interner: ctx.interner
                ))
                let makeBody = try findKIRFunctionBody(named: "make8", in: module, interner: ctx.interner)
                let objectFactoryCall = try #require(makeBody.first { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                        return false
                    }
                    return ctx.interner.resolve(callee).hasPrefix("kk_object_literal_")
                })

                guard case let .call(factorySymbol, callee, arguments, result, _, _, _, _) = objectFactoryCall else {
                    Issue.record("Expected object literal to lower to generated factory call.")
                    return
                }

                let generatedFactorySymbol = try #require(factorySymbol)
                #expect(generatedFactorySymbol.rawValue != 0)
                #expect(generatedFactorySymbol != .invalid)
                #expect(ctx.interner.resolve(callee).hasPrefix("kk_object_literal_"))
                #expect(arguments.isEmpty)
                let resultExprID = try #require(result)
                #expect(module.arena.exprType(resultExprID) == sema.bindings.exprTypes[makeExprID])
                if case .unit? = module.arena.expr(resultExprID) {
                    Issue.record("Object literal must not lower to unit.")
                }

                let generatedFactoryDeclIndex = try #require(module.arena.declarations.firstIndex(where: { decl in
                    guard case let .function(function) = decl else {
                        return false
                    }
                    return function.symbol == generatedFactorySymbol
                }))
                guard case let .function(generatedFactory) = module.arena.declarations[generatedFactoryDeclIndex] else {
                    Issue.record("Expected generated object factory function declaration.")
                    return
                }
                let hasAllocationRuntimeCall = generatedFactory.body.contains { instruction in
                    guard case let .call(_, loweredCallee, _, _, _, _, _, _) = instruction else {
                        return false
                    }
                    let calleeName = ctx.interner.resolve(loweredCallee)
                    return calleeName == "kk_alloc" || calleeName == "kk_array_new" || calleeName == "kk_object_new"
                }
                #expect(
                    hasAllocationRuntimeCall,
                    "Expected generated object factory to include allocation runtime call."
                )

                let generatedNominalDeclIndex = try #require(module.arena.declarations.firstIndex(where: { decl in
                    guard case let .nominalType(nominal) = decl else {
                        return false
                    }
                    return sema.symbols.symbol(nominal.symbol) == nil
                }))

                let generatedFactoryDeclID = KIRDeclID(rawValue: Int32(generatedFactoryDeclIndex))
                let generatedNominalDeclID = KIRDeclID(rawValue: Int32(generatedNominalDeclIndex))
                let fileDeclIDs = Set(module.files.flatMap(\.decls))
                #expect(fileDeclIDs.contains(generatedFactoryDeclID))
                #expect(fileDeclIDs.contains(generatedNominalDeclID))
            }

            // sample8: object literal stored-property read uses non-throwing fast path
            do {
                let body = try findKIRFunctionBody(named: "main9", in: module, interner: ctx.interner)
                let callNames = extractCallees(from: body, interner: ctx.interner)
                #expect(callNames.contains("kk_array_get_inbounds"))

                let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
                #expect(throwFlags["kk_array_get_inbounds"]?.allSatisfy { $0 == false } == true)
            }

            // sample9: object literal custom getter uses accessor call
            do {
                let body = try findKIRFunctionBody(named: "main10", in: module, interner: ctx.interner)
                let callNames = extractCallees(from: body, interner: ctx.interner)
                #expect(!(callNames.contains("kk_array_get")))
                #expect(callNames.contains("get"))
            }
        }
    }

    // MARK: - Lambda / CallableRef Lowering (P5-20)
}
#endif
