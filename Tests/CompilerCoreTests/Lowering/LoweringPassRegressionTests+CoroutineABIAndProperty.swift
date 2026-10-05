#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LoweringPassRegressionTests {
    @Test
    func testCoroutineDurationArgumentsUseMillisecondStorageBridge() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlin.time.Duration.Companion.milliseconds

        fun main() = runBlocking {
            delay(5.milliseconds)
            withTimeout(10_000_000_000_000L.milliseconds) { 42 }
            withTimeoutOrNull(10_000_000_000_000L.milliseconds) { 43 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "DurationCoroutineStorage", emit: .kirDump)
            try runToLowering(ctx)
            let module = try #require(ctx.kir)
            let callees = findAllKIRFunctions(in: module).flatMap {
                extractCallees(from: $0.body, interner: ctx.interner)
            }
            #expect(callees.filter { $0 == "kk_duration_inWholeMilliseconds" }.count == 3)
            #expect(callees.contains("kk_kxmini_delay"))
            #expect(callees.contains("kk_with_timeout"))
            #expect(callees.contains("kk_with_timeout_or_null"))
        }
    }

    // MARK: - Coroutine Launcher Arg Tests

    @Test(arguments: [true, false])
    func testCoroutineLauncherWithArgBearingSuspendFunctionGeneratesThunk(routesThrows: Bool) throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 800)
        let suspendSymbol = SymbolID(rawValue: 801)
        let suspendParamSymbol = SymbolID(rawValue: 802)

        let funcRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let argExpr = arena.appendExpr(.intLiteral(42))
        let launcherResult = arena.appendExpr(.temporary(2))
        let thrownResult = routesThrows ? arena.appendTemporary(type: types.nullableAnyType) : nil

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .constValue(result: argExpr, value: .intLiteral(42)),
                .call(
                    symbol: nil,
                    callee: interner.intern("runBlocking"),
                    arguments: [funcRefExpr, argExpr],
                    result: launcherResult,
                    canThrow: false,
                    thrownResult: thrownResult
                ),
                .returnValue(launcherResult),
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("compute"),
            params: [KIRParameter(symbol: suspendParamSymbol, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [.returnValue(arena.appendExpr(.symbolRef(suspendParamSymbol)))],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "LauncherArgTest")

        let thunkFunctions = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
            return interner.resolve(fn.name).hasPrefix("kk_launcher_thunk_") ? fn : nil
        }
        #expect(thunkFunctions.count == 1)
        let thunk = try #require(thunkFunctions.first)
        #expect(thunk.params.count == 1)

        let thunkCallees = extractCallees(from: thunk.body, interner: interner)
        #expect(thunkCallees.contains("kk_coroutine_launcher_arg_get"))
        #expect(thunkCallees.contains(where: { $0.hasPrefix("kk_suspend_") }))

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_coroutine_continuation_new"))
        #expect(mainCallees.contains("kk_coroutine_launcher_arg_set"))
        #expect(mainCallees.contains("kk_kxmini_run_blocking_with_cont"))
        #expect(!mainCallees.contains("runBlocking"))

        let blockingCall = try #require(loweredMain.body.first { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
            return interner.resolve(callee) == "kk_kxmini_run_blocking_with_cont"
        })
        if case let .call(_, _, _, _, canThrow, loweredThrownResult, _, _) = blockingCall {
            #expect(canThrow)
            #expect(loweredThrownResult == thrownResult)
        }

        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test
    func testCoroutineLauncherZeroArgSuspendStillUsesOriginalPath() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 810)
        let suspendSymbol = SymbolID(rawValue: 811)

        let funcRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let launcherResult = arena.appendExpr(.temporary(1))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("runBlocking"),
                    arguments: [funcRefExpr],
                    result: launcherResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(launcherResult),
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("simple"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "LauncherZeroArgTest")

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_kxmini_run_blocking"))
        #expect(!mainCallees.contains("kk_kxmini_run_blocking_with_cont"))
        #expect(!mainCallees.contains("kk_coroutine_launcher_arg_set"))
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test
    func testFlowSymbolPropagationConvergesWhenSymbolExprIsOverwritten() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let symbolA = SymbolID(rawValue: 820)
        let symbolB = SymbolID(rawValue: 821)
        let mainSymbol = SymbolID(rawValue: 822)

        let exprA = arena.appendExpr(.symbolRef(symbolA))
        let exprB = arena.appendExpr(.symbolRef(symbolB))
        let lambdaExpr = arena.appendExpr(.symbolRef(SymbolID(rawValue: 823)))
        let mapResult = arena.appendExpr(.temporary(3))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .constValue(result: exprA, value: .symbolRef(symbolA)),
                .constValue(result: exprB, value: .symbolRef(symbolB)),
                .copy(from: exprA, to: exprB),
                .call(
                    symbol: nil,
                    callee: interner.intern("map"),
                    arguments: [exprB, lambdaExpr],
                    result: mapResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(mapResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )
        let ctx = makeKIRContext(
            moduleName: "FlowSymbolPropagationConvergence",
            interner: interner
        )

        try CoroutineLoweringPass().run(module: module, ctx: ctx)

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let callees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(callees.contains("map"))
        #expect(!callees.contains("kk_flow_emit"))
    }

    @Test
    func testCreateCoroutineUninterceptedWithoutReceiverLoweringUsesCompletionState() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 850)
        let suspendSymbol = SymbolID(rawValue: 851)

        let functionRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let completionExpr = arena.appendExpr(.intLiteral(17))
        let callResult = arena.appendExpr(.temporary(2))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("createCoroutineUnintercepted"),
                    arguments: [functionRefExpr, completionExpr],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("makeContinuation"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "CreateCoroutineUninterceptedNoReceiverTest")

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_create_coroutine_unintercepted"))
        #expect(!mainCallees.contains("kk_coroutine_continuation_new"))
        #expect(!mainCallees.contains("kk_coroutine_state_set_completion"))
        #expect(!mainCallees.contains("kk_coroutine_launcher_arg_set"))
        #expect(!mainCallees.contains("createCoroutineUnintercepted"))
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test
    func testCreateCoroutineWithoutReceiverLoweringUsesCompletionState() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 865)
        let suspendSymbol = SymbolID(rawValue: 866)

        let functionRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let completionExpr = arena.appendExpr(.intLiteral(17))
        let callResult = arena.appendExpr(.temporary(2))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("createCoroutine"),
                    arguments: [functionRefExpr, completionExpr],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("makeContinuation"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "CreateCoroutineNoReceiverTest")

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_create_coroutine_unintercepted"))
        #expect(!mainCallees.contains("createCoroutine"))
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test
    func testCreateCoroutineUninterceptedWithReceiverLoweringStoresReceiverArg() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 860)
        let suspendSymbol = SymbolID(rawValue: 861)
        let receiverParamSymbol = SymbolID(rawValue: 862)

        let functionRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let receiverExpr = arena.appendExpr(.intLiteral(41))
        let completionExpr = arena.appendExpr(.intLiteral(17))
        let callResult = arena.appendExpr(.temporary(3))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("createCoroutineUnintercepted"),
                    arguments: [functionRefExpr, receiverExpr, completionExpr],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("makeContinuationWithReceiver"),
            params: [KIRParameter(symbol: receiverParamSymbol, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "CreateCoroutineUninterceptedWithReceiverTest")

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_create_coroutine_unintercepted"))
        #expect(mainCallees.contains("kk_coroutine_launcher_arg_set"))
        #expect(!mainCallees.contains("kk_coroutine_continuation_new"))
        #expect(!mainCallees.contains("kk_coroutine_state_set_completion"))
        #expect(!mainCallees.contains("createCoroutineUnintercepted"))
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test
    func testStartCoroutineUninterceptedOrReturnLoweringUsesRuntimeEntryPoint() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 870)
        let suspendSymbol = SymbolID(rawValue: 871)

        let functionRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let completionExpr = arena.appendExpr(.intLiteral(17))
        let callResult = arena.appendExpr(.temporary(2))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("startCoroutineUninterceptedOrReturn"),
                    arguments: [functionRefExpr, completionExpr],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("startNow"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "StartCoroutineUninterceptedTest")

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_create_coroutine_unintercepted"))
        #expect(mainCallees.contains("kk_start_coroutine_unintercepted_or_return"))
        #expect(!mainCallees.contains("startCoroutineUninterceptedOrReturn"))
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test
    func testStartCoroutineUninterceptedOrReturnWithReceiverStoresReceiverArg() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 880)
        let suspendSymbol = SymbolID(rawValue: 881)
        let receiverParamSymbol = SymbolID(rawValue: 882)

        let functionRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let receiverExpr = arena.appendExpr(.intLiteral(41))
        let completionExpr = arena.appendExpr(.intLiteral(17))
        let callResult = arena.appendExpr(.temporary(3))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("startCoroutineUninterceptedOrReturn"),
                    arguments: [functionRefExpr, receiverExpr, completionExpr],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("startWithReceiver"),
            params: [KIRParameter(symbol: receiverParamSymbol, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "StartCoroutineUninterceptedReceiverTest")

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_create_coroutine_unintercepted"))
        #expect(mainCallees.contains("kk_coroutine_launcher_arg_set"))
        #expect(mainCallees.contains("kk_start_coroutine_unintercepted_or_return"))
        #expect(!mainCallees.contains("startCoroutineUninterceptedOrReturn"))
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test
    func testStartCoroutineWithoutReceiverLoweringCreatesAndResumesContinuation() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 890)
        let suspendSymbol = SymbolID(rawValue: 891)

        let functionRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let completionExpr = arena.appendExpr(.intLiteral(17))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("startCoroutine"),
                    arguments: [functionRefExpr, completionExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("startPublic"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "StartCoroutineNoReceiverTest")

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_create_coroutine_unintercepted"))
        #expect(mainCallees.contains("kk_coroutine_continuation_resume"))
        #expect(!mainCallees.contains("kk_start_coroutine_unintercepted_or_return"))
        #expect(!mainCallees.contains("kk_coroutine_launcher_arg_set"))
        #expect(!mainCallees.contains("startCoroutine"))
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test
    func testStartCoroutineWithReceiverLoweringStoresReceiverArgAndResumesContinuation() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 900)
        let suspendSymbol = SymbolID(rawValue: 901)
        let receiverParamSymbol = SymbolID(rawValue: 902)

        let functionRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let receiverExpr = arena.appendExpr(.intLiteral(41))
        let completionExpr = arena.appendExpr(.intLiteral(17))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("startCoroutine"),
                    arguments: [functionRefExpr, receiverExpr, completionExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("startPublicWithReceiver"),
            params: [KIRParameter(symbol: receiverParamSymbol, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "StartCoroutineReceiverTest")

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_create_coroutine_unintercepted"))
        #expect(mainCallees.contains("kk_coroutine_launcher_arg_set"))
        #expect(mainCallees.contains("kk_coroutine_continuation_resume"))
        #expect(!mainCallees.contains("kk_start_coroutine_unintercepted_or_return"))
        #expect(!mainCallees.contains("startCoroutine"))
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test
    func testCoroutineLauncherWithSuspendLambdaCapturesGeneratesThunk() throws {
        // Simulates: val x = 42; runBlocking { x }
        // The lambda captures `x`, so it has 1 capture param and 0 value params.
        // The launcher call should include the capture value as an extra arg,
        // and the CoroutineLoweringPass should generate a thunk that forwards it.
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 820)
        let lambdaSymbol = SymbolID(rawValue: 821)
        let captureParamSymbol = SymbolID(rawValue: 822)

        let captureValueExpr = arena.appendExpr(.intLiteral(42))
        let lambdaRefExpr = arena.appendExpr(.symbolRef(lambdaSymbol))
        let launcherResult = arena.appendExpr(.temporary(2))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .constValue(result: captureValueExpr, value: .intLiteral(42)),
                .constValue(result: lambdaRefExpr, value: .symbolRef(lambdaSymbol)),
                .call(
                    symbol: nil,
                    callee: interner.intern("runBlocking"),
                    arguments: [lambdaRefExpr, captureValueExpr],
                    result: launcherResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(launcherResult),
            ],
            isSuspend: false,
            isInline: false
        )

        // Lambda function with 1 capture param, isSuspend: true
        let lambdaFn = KIRFunction(
            symbol: lambdaSymbol,
            name: interner.intern("kk_lambda_99"),
            params: [KIRParameter(symbol: captureParamSymbol, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [.returnValue(arena.appendExpr(.symbolRef(captureParamSymbol)))],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "LauncherLambdaCaptureTest")

        let thunkFunctions = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
            return interner.resolve(fn.name).hasPrefix("kk_launcher_thunk_") ? fn : nil
        }
        #expect(thunkFunctions.count == 1)
        let thunk = try #require(thunkFunctions.first)
        #expect(thunk.params.count == 1)

        let thunkCallees = extractCallees(from: thunk.body, interner: interner)
        #expect(thunkCallees.contains("kk_coroutine_launcher_arg_get"))
        #expect(thunkCallees.contains(where: { $0.hasPrefix("kk_suspend_") }))

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_coroutine_continuation_new"))
        #expect(mainCallees.contains("kk_coroutine_launcher_arg_set"))
        #expect(mainCallees.contains("kk_kxmini_run_blocking_with_cont"))
        #expect(!mainCallees.contains("runBlocking"))

        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test
    func testCoroutineLauncherWithZeroCapturesSuspendLambdaUsesOriginalPath() throws {
        // Simulates: runBlocking { 42 }
        // The lambda has no captures and no value params → uses zero-arg path.
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 830)
        let lambdaSymbol = SymbolID(rawValue: 831)

        let lambdaRefExpr = arena.appendExpr(.symbolRef(lambdaSymbol))
        let launcherResult = arena.appendExpr(.temporary(1))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .constValue(result: lambdaRefExpr, value: .symbolRef(lambdaSymbol)),
                .call(
                    symbol: nil,
                    callee: interner.intern("runBlocking"),
                    arguments: [lambdaRefExpr],
                    result: launcherResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(launcherResult),
            ],
            isSuspend: false,
            isInline: false
        )

        // Lambda with no params (no captures, no value params)
        let lambdaFn = KIRFunction(
            symbol: lambdaSymbol,
            name: interner.intern("kk_lambda_100"),
            params: [],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [.returnValue(arena.appendExpr(.intLiteral(42)))],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "LauncherLambdaZeroCaptureTest")

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_kxmini_run_blocking"))
        #expect(!mainCallees.contains("kk_kxmini_run_blocking_with_cont"))
        #expect(!mainCallees.contains("kk_coroutine_launcher_arg_set"))
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test
    func testCoroutineLauncherLaunchWithSuspendLambdaCapturesGeneratesThunk() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 840)
        let lambdaSymbol = SymbolID(rawValue: 841)
        let captureParamSymbol = SymbolID(rawValue: 842)

        let captureValueExpr = arena.appendExpr(.intLiteral(10))
        let lambdaRefExpr = arena.appendExpr(.symbolRef(lambdaSymbol))
        let launcherResult = arena.appendExpr(.temporary(2))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .constValue(result: captureValueExpr, value: .intLiteral(10)),
                .constValue(result: lambdaRefExpr, value: .symbolRef(lambdaSymbol)),
                .call(
                    symbol: nil,
                    callee: interner.intern("launch"),
                    arguments: [lambdaRefExpr, captureValueExpr],
                    result: launcherResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(launcherResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let lambdaFn = KIRFunction(
            symbol: lambdaSymbol,
            name: interner.intern("kk_lambda_101"),
            params: [KIRParameter(symbol: captureParamSymbol, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "LauncherLaunchLambdaTest")

        let thunkFunctions = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
            return interner.resolve(fn.name).hasPrefix("kk_launcher_thunk_") ? fn : nil
        }
        #expect(thunkFunctions.count == 1)

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_kxmini_launch_with_cont"))
        #expect(mainCallees.contains("kk_coroutine_launcher_arg_set"))
        #expect(!mainCallees.contains("launch"))

        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    // MARK: - produce/actor Function-Value Block Tests

    @Test
    func testProduceLaunchFunctionValuePacksCapturesIntoEnvArg() throws {
        // Simulates KUU-951: `produce(block = f)` where `f` is a stored
        // suspend function value capturing `x`. The value's thunk is
        // capture-first, so `__kk_produce_launch` must be invoked with the
        // explicit (fnPtr, env) pair — env materialized at the call site
        // from the value's callable info — not the launcher-continuation
        // convention literals use.
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 830)
        let suspendSymbol = SymbolID(rawValue: 831)
        let suspendParamSymbol = SymbolID(rawValue: 832)

        let channelExpr = arena.appendExpr(.intLiteral(7))
        let captureExpr = arena.appendExpr(.intLiteral(42))
        let suspendRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let produceResult = arena.appendExpr(.temporary(3))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .constValue(result: channelExpr, value: .intLiteral(7)),
                .constValue(result: captureExpr, value: .intLiteral(42)),
                .constValue(result: suspendRefExpr, value: .symbolRef(suspendSymbol)),
                .call(
                    symbol: nil,
                    callee: interner.intern("__kk_produce_launch"),
                    arguments: [channelExpr, suspendRefExpr],
                    result: produceResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(produceResult),
            ],
            isSuspend: false,
            isInline: false
        )
        // A *named* suspend function — not a `kk_lambda_<exprID>` literal —
        // so it is never coroutine-launcher marked.
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("named_suspend_block"),
            params: [KIRParameter(symbol: suspendParamSymbol, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [.returnValue(arena.appendExpr(.symbolRef(suspendParamSymbol)))],
            isSuspend: true,
            isInline: false
        )

        arena.callableValueInfoByExprID[suspendRefExpr] = KIRCallableValueInfo(
            symbol: suspendSymbol,
            callee: interner.intern("named_suspend_block"),
            captureArguments: [captureExpr],
            hasClosureParam: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "ProduceValueEnvTest")

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let launchCalls = loweredMain.body.compactMap { instruction -> [KIRExprID]? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  interner.resolve(callee) == "__kk_produce_launch"
            else { return nil }
            return arguments
        }
        let launchArgs = try #require(launchCalls.first)
        #expect(launchArgs.count == 3)
        // With one capture the env slot is the raw capture value itself.
        #expect(launchArgs[2] == captureExpr)

        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(!mainCallees.contains("kk_coroutine_launcher_arg_set"))
        #expect(!mainCallees.contains("kk_function_value_fn_ptr"))
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    @Test
    func testProduceLaunchOpaqueFunctionValueUsesRuntimeAccessors() throws {
        // Same call shape but with no callable info recorded for the value:
        // (fnPtr, env) must be recovered at runtime through the
        // `kk_function_value_*` accessors.
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 840)
        let suspendSymbol = SymbolID(rawValue: 841)
        let suspendParamSymbol = SymbolID(rawValue: 842)

        let channelExpr = arena.appendExpr(.intLiteral(7))
        let suspendRefExpr = arena.appendExpr(.symbolRef(suspendSymbol))
        let produceResult = arena.appendExpr(.temporary(3))

        let mainFn = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.nullableAnyType,
            body: [
                .constValue(result: channelExpr, value: .intLiteral(7)),
                .constValue(result: suspendRefExpr, value: .symbolRef(suspendSymbol)),
                .call(
                    symbol: nil,
                    callee: interner.intern("__kk_produce_launch"),
                    arguments: [channelExpr, suspendRefExpr],
                    result: produceResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(produceResult),
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendFn = KIRFunction(
            symbol: suspendSymbol,
            name: interner.intern("named_suspend_block"),
            params: [KIRParameter(symbol: suspendParamSymbol, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [.returnValue(arena.appendExpr(.symbolRef(suspendParamSymbol)))],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let ctx = try runLowering(module: module, interner: interner, moduleName: "ProduceValueOpaqueTest")

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "expected lowered main function")
        let mainCallees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(mainCallees.contains("kk_function_value_fn_ptr"))
        #expect(mainCallees.contains("kk_function_value_closure_raw"))
        #expect(!mainCallees.contains("kk_coroutine_launcher_arg_set"))

        let launchCalls = loweredMain.body.compactMap { instruction -> [KIRExprID]? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  interner.resolve(callee) == "__kk_produce_launch"
            else { return nil }
            return arguments
        }
        #expect(launchCalls.first?.count == 3)
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }

    // MARK: - ABI Boxing/Unboxing Tests
}
#endif
