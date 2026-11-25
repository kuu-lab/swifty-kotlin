#if canImport(Testing)
@testable import CompilerCore
import RuntimeABI
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {

    private static let _sharedControlFlowCtx = Result<CompilationContext, any Error> {
        let sources: [String] = [
            """
            package sample0
            fun sideEffect0(x: Int): Int = x
            fun test0(flag: Boolean): Int {
                if (flag) sideEffect0(1) else sideEffect0(2)
                return 0
            }
            """,
            """
            package sample1
            fun earlyReturn1(flag: Boolean): Int {
                val result = if (flag) return 42 else 0
                return result
            }
            """,
            """
            package sample2
            fun effect2(x: Int): Int = x
            fun test2(v: Int): Int = when (v) { 1 -> effect2(10), 2 -> effect2(20), else -> effect2(30) }
            """,
            """
            package sample3
            class MyErr

            fun bodyCall3(x: Int): Int = x
            fun catchCall3(x: Int): Int = x + 1
            fun finallyCall3(): Int = 0

            fun demo3(v: Int): Int {
                return try {
                    bodyCall3(v)
                } catch (e: Int) {
                    catchCall3(e)
                } catch (e: MyErr) {
                    7
                } finally {
                    finallyCall3()
                }
            }
            """,
            """
            package sample4
            class MyException

            fun riskyCall4(): Int = 42

            fun demo4(): Int {
                return try {
                    riskyCall4()
                } catch (e: MyException) {
                    -1
                }
            }
            """,
            """
            package sample5
            class ErrA
            class ErrB

            fun riskyCall5(): Int = 42

            fun demo5(): Int {
                return try {
                    riskyCall5()
                } catch (e: ErrA) {
                    -1
                } catch (e: ErrB) {
                    -2
                }
            }
            """,
            """
            package sample6
            fun riskyCall6(): Int = 42

            fun demo6(): Int {
                return try {
                    riskyCall6()
                } catch (e: Any) {
                    -1
                }
            }
            """,
            """
            package sample7
            interface Marker
            fun make7(): Marker = object : Marker {}
            """,
            """
            package sample8
            fun main8(): Int {
                val instance = object {
                    val value: Int = 7
                }
                return instance.value
            }
            """,
            """
            package sample9
            fun main9(): Int {
                val instance = object {
                    val seed: Int = 7
                    val value: Int
                        get() = seed + 1
                }
                return instance.value
            }
            """
        ]
        let ctx = makeContextFromSources(sources)
        try runToKIR(ctx)
        return ctx
    }

    private func sharedControlFlowCtx() throws -> CompilationContext {
        try Self._sharedControlFlowCtx.get()
    }

    @Test
    func testIfExprSideEffectsDoNotLeakFromUnselectedBranch() throws {
        let ctx = try sharedControlFlowCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "test0", in: module, interner: ctx.interner)

        let sideEffectCallsCount = extractCallees(from: body, interner: ctx.interner).count { $0 == "sideEffect0" }
        #expect(sideEffectCallsCount == 2, "Both branches should have sideEffect0 calls in IR")

        let jumpIfEqualCount = body.count { if case .jumpIfEqual = $0 { return true }; return false }
        #expect(jumpIfEqualCount >= 1, "Condition should guard branch entry via jumpIfEqual")
    }



    @Test
    func testIfExprReturnInUnselectedBranchDoesNotLeak() throws {
        let ctx = try sharedControlFlowCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "earlyReturn1", in: module, interner: ctx.interner)

        let labelCount = body.count { if case .label = $0 { return true }; return false }
        #expect(labelCount >= 2, "return-in-branch needs labels for control flow")

        let hasReturnValue = body.contains { if case .returnValue = $0 { return true }; return false }
        #expect(hasReturnValue, "Branch with return 42 should emit returnValue")
    }



    @Test
    func testWhenExprSideEffectsDoNotLeakFromUnselectedBranch() throws {
        let ctx = try sharedControlFlowCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "test2", in: module, interner: ctx.interner)

        let effectCallsCount = extractCallees(from: body, interner: ctx.interner).count { $0 == "effect2" }
        #expect(effectCallsCount == 3, "All 3 branches should have effect2 calls in IR")

        let labelCount = body.count { if case .label = $0 { return true }; return false }
        #expect(labelCount >= 3, "Each branch needs labels for control flow")
    }



    @Test
    func testTryCatchFinallyLoweringUsesOrderedTypeDispatchAndThrownSlotRouting() throws {
        let ctx = try sharedControlFlowCtx()

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)

        let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: ctx.options.inputs[3]))
        let tryExprID = try #require(firstExprID(in: ast) { exprID, expr in
            guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else {
                return false
            }
            if case .tryExpr = expr {
                return true
            }
            return false
        })
        guard case let .tryExpr(_, catchClauses, _, _)? = ast.arena.expr(tryExprID) else {
            Issue.record("Expected try expression in demo3.")
            return
        }
        #expect(catchClauses.count == 2)

        let catchBindings = try catchClauses.map { clause in
            try #require(sema.bindings.catchClauseBinding(for: clause.body))
        }
        #expect(catchBindings[0].parameterSymbol != .invalid)
        #expect(catchBindings[1].parameterSymbol != .invalid)

        let body = try findKIRFunctionBody(named: "demo3", in: module, interner: ctx.interner)
        let runtimeNames = Set(RuntimeABIExterns.allExterns.map(\.name))
        let matcherCalls = body.compactMap { instruction -> KIRInstruction? in
            guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                  symbol == nil,
                  !runtimeNames.contains(ctx.interner.resolve(callee))
            else {
                return nil
            }
            return instruction
        }
        #expect(matcherCalls.isEmpty, "Try-catch lowering must not emit undeclared runtime helpers.")

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

        guard let bodyEdge = thrownEdge(for: "bodyCall3"),
              let catchEdge = thrownEdge(for: "catchCall3"),
              let finallyEdge = thrownEdge(for: "finallyCall3")
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
            Issue.record("Expected catchCall3 argument in first catch body.")
            return
        }
        #expect(module.arena.exprType(firstCatchArgument) == catchBindings[0].parameterType)
    }


    @Test
    func testTryCatchUnknownTokenUsesRuntimeTypeCheck() throws {
        let runtime = try RuntimeNames()
        let ctx = try sharedControlFlowCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "demo4", in: module, interner: ctx.interner)

        let opIsCalls = body.filter { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
            return callee == ctx.interner.intern(runtime[.isType])
        }
        #expect(opIsCalls.count >= 1, "Expected at least one kk_op_is call for runtime type check fallback on UNKNOWN token.")

        let firstOpIsCall = try #require(opIsCalls.first)
        if case let .call(_, _, arguments, _, _, _, _, _) = firstOpIsCall {
            #expect(arguments.count == 2, "Runtime type tests should receive exception value and type token.")
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


    @Test
    func testTryCatchMultipleClausesUnknownTokenUsesRuntimeTypeCheck() throws {
        let runtime = try RuntimeNames()
        let ctx = try sharedControlFlowCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "demo5", in: module, interner: ctx.interner)

        let opIsCount = extractCallees(from: body, interner: ctx.interner).count { $0 == runtime[.isType] }
        #expect(opIsCount >= 2, "Expected at least one kk_op_is call per typed catch clause for runtime type check fallback.")
    }


    @Test
    func testTryCatchCatchAllDoesNotEmitRuntimeTypeCheck() throws {
        let runtime = try RuntimeNames()
        let ctx = try sharedControlFlowCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "demo6", in: module, interner: ctx.interner)

        let opIsCount = extractCallees(from: body, interner: ctx.interner).count { $0 == runtime[.isType] }
        #expect(opIsCount == 0, "catch-all (Any) should not emit kk_op_is runtime type check.")
    }



    @Test
    func testBuildKIRLowersEmptyBodyObjectLiteralToInlineRuntimeObjectEntity() throws {
        let runtime = try RuntimeNames()
        let ctx = try sharedControlFlowCtx()

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let makeExprID = try #require(topLevelExpressionBodyExprID(
            named: "make7",
            ast: ast,
            interner: ctx.interner
        ))
        let makeBody = try findKIRFunctionBody(named: "make7", in: module, interner: ctx.interner)

        #expect(extractCallees(from: makeBody, interner: ctx.interner).allSatisfy {
            RuntimeABIExterns.externDecl(named: $0) != nil
        }, "Inline object allocation must use declared runtime helpers without a generated factory call")

        let allocationCall = try #require(makeBody.first { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                return false
            }
            return callee == ctx.interner.intern(runtime[.objectNew])
        })
        guard case let .call(_, _, arguments, result, _, _, _, _) = allocationCall else {
            Issue.record("Expected object literal to lower to a kk_object_new call.")
            return
        }

        #expect(arguments.count == 2)
        if case let .intLiteral(classID)? = module.arena.expr(arguments[1]) {
            #expect(classID != 0, "Expected the object literal's own stable nominal type ID.")
        } else {
            Issue.record("Expected a constant classID argument to kk_object_new.")
        }

        let resultExprID = try #require(result)
        #expect(module.arena.exprType(resultExprID) == sema.bindings.exprTypes[makeExprID])
        if case .unit? = module.arena.expr(resultExprID) {
            Issue.record("Object literal must not lower to unit.")
        }

        let objectValueType = try #require(sema.bindings.exprTypes[makeExprID])
        guard case let .classType(objectClassType) = sema.types.kind(of: objectValueType) else {
            Issue.record("Expected the object literal to have its own anonymous class type.")
            return
        }
        let objectSymbol = objectClassType.classSymbol
        let objectSymbolName = try #require(sema.symbols.symbol(objectSymbol)?.name)
        #expect(ctx.interner.resolve(objectSymbolName).hasPrefix("__ObjectLiteral_"))

        let nominalDeclIndex = try #require(module.arena.declarations.firstIndex(where: { decl in
            guard case let .nominalType(nominal) = decl else {
                return false
            }
            return nominal.symbol == objectSymbol
        }))
        let fileDeclIDs = Set(module.files.flatMap(\.decls))
        #expect(fileDeclIDs.contains(KIRDeclID(rawValue: Int32(nominalDeclIndex))))
    }



    @Test
    func testBuildKIRObjectLiteralStoredPropertyReadUsesNonThrowingFastPath() throws {
        let runtime = try RuntimeNames()
        let ctx = try sharedControlFlowCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main8", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: body, interner: ctx.interner)
        #expect(callNames.contains(runtime[.arrayGetInbounds]))

        let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
        #expect(throwFlags[runtime[.arrayGetInbounds]]?.allSatisfy { $0 == false } == true)
    }



    @Test
    func testBuildKIRObjectLiteralCustomGetterUsesAccessorCall() throws {
        let runtime = try RuntimeNames()
        let ctx = try sharedControlFlowCtx()

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main9", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: body, interner: ctx.interner)
        #expect(!(callNames.contains(runtime[.arrayGet])))
        #expect(callNames.contains("get"))

        let getterBodies = module.arena.declarations.compactMap { decl -> [KIRInstruction]? in
            guard case let .function(function) = decl,
                  function.name == KnownCompilerNames(interner: ctx.interner).get,
                  function.params.count == 1
            else {
                return nil
            }
            return function.body
        }
        #expect(!getterBodies.isEmpty, "Expected the object literal's `get` accessor to be emitted.")

        func containsUnitConstant(_ instructions: [KIRInstruction]) -> Bool {
            instructions.contains { instruction in
                guard case let .constValue(_, value) = instruction else {
                    return false
                }
                if case .unit = value {
                    return true
                }
                return false
            }
        }
        func readsInstanceField(_ instructions: [KIRInstruction]) -> Bool {
            instructions.contains { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return callee == ctx.interner.intern(runtime[.arrayGetInbounds])
            }
        }

        #expect(
            getterBodies.contains(where: readsInstanceField),
            "Expected a custom getter body to read its sibling property off the instance."
        )
        #expect(
            !getterBodies.contains(where: containsUnitConstant),
            "A `.unit` constant in an accessor body means an identifier went unresolved."
        )
    }


}
#endif
