#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

extension LoweringPassRegressionTests {

    @Test(arguments: [false, true])
    func testClosureConversionDoesNotEmitWrapperForInlineOnlyCapture(hasMarker: Bool) throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let captureSymbol = SymbolID(rawValue: -2_000_042)
        let valueSymbol = SymbolID(rawValue: -1_000_042)
        let capturedValue = arena.appendExpr(.symbolRef(captureSymbol), type: types.intType)
        let lambda = KIRFunction(
            symbol: SymbolID(rawValue: 2),
            name: interner.intern("kk_lambda_42"),
            params: [
                KIRParameter(symbol: captureSymbol, type: types.intType),
                KIRParameter(symbol: valueSymbol, type: types.intType),
            ],
            returnType: types.intType,
            body: [.returnValue(capturedValue)],
            isSuspend: false,
            isInline: false,
            isInlineOnly: true
        )
        var body: [KIRInstruction] = []
        if hasMarker {
            body.append(.call(callee: interner.intern("<lambda>"), arguments: [], result: nil, canThrow: false))
        }
        body.append(.returnUnit)
        let mainID = arena.appendDecl(.function(KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )))
        let lambdaID = arena.appendDecl(.function(lambda))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID, lambdaID])],
            arena: arena
        )
        let ctx = makeKIRContext(
            moduleName: "InlineOnlyCapture",
            interner: interner,
            sema: makeSemaModule(types: types).ctx
        )
        let pass = LambdaClosureConversionPass()
        #expect(pass.shouldRun(module: module, ctx: ctx) == hasMarker)
        try pass.run(module: module, ctx: ctx)
        #expect(arena.declarations.count == 2)
    }

    @Test
    func testClosureConversionRewritesLambdaMarkerToKkLambdaInvoke() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSym = SymbolID(rawValue: 1)
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    callee: interner.intern("<lambda>"),
                    arguments: [v0],
                    result: v1,
                    canThrow: false
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let ctx = makeKIRContext(
            moduleName: "ClosureTest",
            interner: interner
        )

        #expect(pass.shouldRun(module: module, ctx: ctx))
        try pass.run(module: module, ctx: ctx)

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "Expected lowered main function.")

        let callees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(callees.contains(CompilerCall.lambdaInvoke.name),
            "Expected <lambda> to be rewritten to kk_lambda_invoke")
        #expect(!callees.contains("<lambda>"),
            "Expected <lambda> marker to be removed")
    }

    @Test
    func testClosureConversionSynthesizesClosureObjectForLambdaWithCaptures() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 1)
        let lambdaSym = SymbolID(rawValue: 2)
        let lambdaName = interner.intern("kk_lambda_42")

        // Capture param: uses the negative range that LambdaLowerer assigns.
        let captureParamSym = SymbolID(rawValue: -2_000_042)
        // Value param: also negative but in the -1_000_000 range.
        let valueParamSym = SymbolID(rawValue: -1_000_042)

        let captureExpr = arena.appendExpr(.symbolRef(captureParamSym), type: intType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)
        let bodyResult = arena.appendExpr(.temporary(10), type: intType)

        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: captureParamSym, type: intType),
                KIRParameter(symbol: valueParamSym, type: intType),
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: captureExpr, value: .symbolRef(captureParamSym)),
                .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
                .binary(op: .add, lhs: captureExpr, rhs: valueExpr, result: bodyResult),
                .returnValue(bodyResult),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        let capturedValue = arena.appendExpr(.intLiteral(100), type: intType)
        let callArg = arena.appendExpr(.intLiteral(7), type: intType)
        let callResult = arena.appendExpr(.temporary(20), type: intType)

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: capturedValue, value: .intLiteral(100)),
                .constValue(result: callArg, value: .intLiteral(7)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [capturedValue, callArg],
                    result: callResult,
                    canThrow: false
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let sema = makeSemaModule(types: types).ctx
        let ctx = makeKIRContext(
            moduleName: "ClosureObjTest",
            interner: interner,
            sema: sema
        )

        #expect(pass.shouldRun(module: module, ctx: ctx))
        try pass.run(module: module, ctx: ctx)

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "Expected lowered main function.")

        let callees = extractCallees(from: loweredMain.body, interner: interner)

        #expect(callees.contains(RuntimeCall.objectNew.name),
            "Expected closure object allocation via kk_object_new")

        #expect(callees.contains(RuntimeCall.arraySet.name),
            "Expected capture storage via kk_array_set")

        let invokeWrapperName = interner.resolve(try closureWrapper(for: lambdaSym, in: module).name)
        #expect(callees.contains(invokeWrapperName),
            "Expected invoke wrapper \(invokeWrapperName) to be called")

        #expect(!callees.contains(interner.resolve(lambdaName)),
            "Expected direct lambda call to be replaced by closure invoke")

        let allFunctionNames = findAllKIRFunctions(in: module).map { function in
            interner.resolve(function.name)
        }
        #expect(allFunctionNames.contains(invokeWrapperName),
            "Expected invoke wrapper function to be synthesized")

        let hasNominalType = module.arena.declarations.contains { decl in
            guard case .nominalType = decl else { return false }
            return true
        }
        #expect(hasNominalType,
            "Expected closure object nominal type to be synthesized")
    }

    @Test
    func testClosureConversionSkipsLambdaWithoutCaptures() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 1)
        let lambdaSym = SymbolID(rawValue: 2)
        let lambdaName = interner.intern("kk_lambda_50")

        let valueParamSym = SymbolID(rawValue: -1_000_050)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)

        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: valueParamSym, type: intType),
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
                .returnValue(valueExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        let callArg = arena.appendExpr(.intLiteral(7), type: intType)
        let callResult = arena.appendExpr(.temporary(20), type: intType)

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: callArg, value: .intLiteral(7)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [callArg],
                    result: callResult,
                    canThrow: false
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let ctx = makeKIRContext(
            moduleName: "NoCaptureTest",
            interner: interner
        )

        #expect(!pass.shouldRun(module: module, ctx: ctx))
        try pass.run(module: module, ctx: ctx)

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "Expected lowered main function.")

        let callees = extractCallees(from: loweredMain.body, interner: interner)

        #expect(!callees.contains(RuntimeCall.objectNew.name),
            "Expected no closure object for zero-capture lambda")

        #expect(callees.contains(interner.resolve(lambdaName)),
            "Expected direct lambda call to remain for zero-capture lambda")
    }

    @Test
    func testClosureConversionInvokeWrapperLoadsCaptures() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 1)
        let lambdaSym = SymbolID(rawValue: 3)
        let lambdaName = interner.intern("kk_lambda_99")

        let captureParamSym = SymbolID(rawValue: -2_000_099)
        let valueParamSym = SymbolID(rawValue: -1_000_099)

        let captureExpr = arena.appendExpr(.symbolRef(captureParamSym), type: intType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)

        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: captureParamSym, type: intType),
                KIRParameter(symbol: valueParamSym, type: intType),
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: captureExpr, value: .symbolRef(captureParamSym)),
                .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
                .returnValue(captureExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        let capturedValue = arena.appendExpr(.intLiteral(42), type: intType)
        let callArg = arena.appendExpr(.intLiteral(1), type: intType)
        let callResult = arena.appendExpr(.temporary(30), type: intType)

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: capturedValue, value: .intLiteral(42)),
                .constValue(result: callArg, value: .intLiteral(1)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [capturedValue, callArg],
                    result: callResult,
                    canThrow: false
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let sema = makeSemaModule(types: types).ctx
        let ctx = makeKIRContext(
            moduleName: "InvokeWrapperTest",
            interner: interner,
            sema: sema
        )

        #expect(pass.shouldRun(module: module, ctx: ctx))
        try pass.run(module: module, ctx: ctx)

        let wrapper = try closureWrapper(for: lambdaSym, in: module)

        #expect(wrapper.params.count == 2,
            "Expected invoke wrapper to have 2 params (closureObj + 1 value param)")

        let wrapperCallees = extractCallees(from: wrapper.body, interner: interner)
        #expect(wrapperCallees.contains(RuntimeCall.arrayGetInbounds.name),
            "Expected invoke wrapper to load captures via kk_array_get_inbounds")

        let wrapperCalls = wrapper.body.compactMap { instruction -> (callee: String, canThrow: Bool)? in
            guard case let .call(_, callee, _, _, canThrow, _, _, _) = instruction else {
                return nil
            }
            return (callee: interner.resolve(callee), canThrow: canThrow)
        }
        #expect(wrapperCalls.first(where: { $0.callee == interner.resolve(lambdaName) })?.canThrow == true)

        #expect(wrapperCallees.contains(interner.resolve(lambdaName)),
            "Expected invoke wrapper to forward to original lambda")
    }

    @Test
    func testClosureConversionSkipsCapturedLambdaWithoutMatchingCallSite() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let lambdaSym = SymbolID(rawValue: 4)
        let lambdaName = interner.intern("kk_lambda_60")
        let captureParamSym = SymbolID(rawValue: -2_000_060)
        let valueParamSym = SymbolID(rawValue: -1_000_060)

        let captureExpr = arena.appendExpr(.symbolRef(captureParamSym), type: intType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)

        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: captureParamSym, type: intType),
                KIRParameter(symbol: valueParamSym, type: intType),
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: captureExpr, value: .symbolRef(captureParamSym)),
                .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
                .returnValue(captureExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let ctx = makeKIRContext(
            moduleName: "UnmatchedCaptureCallSiteTest",
            interner: interner
        )

        #expect(!pass.shouldRun(module: module, ctx: ctx))
        try pass.run(module: module, ctx: ctx)

        #expect(findAllKIRFunctions(in: module).map(\.symbol) == [lambdaSym])
    }

    @Test
    func testClosureConversionClassifiesLargeLambdaExprIDSymbols() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 7)
        let lambdaSym = SymbolID(rawValue: 8)
        let lambdaName = interner.intern("kk_lambda_1954")

        let captureParamSym = SymbolID(rawValue: -2_500_224)
        let valueParamSym = SymbolID(rawValue: -1_500_224)
        let captureExpr = arena.appendExpr(.symbolRef(captureParamSym), type: intType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)

        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: captureParamSym, type: intType),
                KIRParameter(symbol: valueParamSym, type: intType),
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: captureExpr, value: .symbolRef(captureParamSym)),
                .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
                .returnValue(valueExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        let capturedValue = arena.appendExpr(.intLiteral(11), type: intType)
        let callArg = arena.appendExpr(.intLiteral(22), type: intType)
        let callResult = arena.appendExpr(.temporary(30), type: intType)
        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: capturedValue, value: .intLiteral(11)),
                .constValue(result: callArg, value: .intLiteral(22)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [capturedValue, callArg],
                    result: callResult,
                    canThrow: false
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        _ = arena.appendDecl(.function(lambdaFn))
        let mainID = arena.appendDecl(.function(mainFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let sema = makeSemaModule(types: types).ctx
        let ctx = makeKIRContext(
            moduleName: "ExprIdBoundaryTest",
            interner: interner,
            sema: sema
        )

        #expect(pass.shouldRun(module: module, ctx: ctx))
        try pass.run(module: module, ctx: ctx)

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "Expected lowered main function.")

        let callees = extractCallees(from: loweredMain.body, interner: interner)
        let wrapper = try closureWrapper(for: lambdaSym, in: module)
        #expect(callees.contains(interner.resolve(wrapper.name)),
            "Expected large-ExprID lambda to be converted")
    }

    @Test
    func testClosureConversionConvertsThrowingLambdaCalls() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 9)
        let lambdaSym = SymbolID(rawValue: 10)
        let lambdaName = interner.intern("kk_lambda_100")

        let captureParamSym = SymbolID(rawValue: -2_000_100)
        let valueParamSym = SymbolID(rawValue: -1_000_100)
        let captureExpr = arena.appendExpr(.symbolRef(captureParamSym), type: intType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)
        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: captureParamSym, type: intType),
                KIRParameter(symbol: valueParamSym, type: intType),
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: captureExpr, value: .symbolRef(captureParamSym)),
                .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
                .returnValue(valueExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        let capturedValue = arena.appendExpr(.intLiteral(11), type: intType)
        let argValue = arena.appendExpr(.intLiteral(22), type: intType)
        let callResult = arena.appendExpr(.temporary(31), type: intType)
        let thrownSlot = arena.appendExpr(.temporary(200), type: intType)
        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: capturedValue, value: .intLiteral(11)),
                .constValue(result: argValue, value: .intLiteral(22)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [capturedValue, argValue],
                    result: callResult,
                    canThrow: true,
                    thrownResult: thrownSlot
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        _ = arena.appendDecl(.function(lambdaFn))
        let mainID = arena.appendDecl(.function(mainFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let sema = makeSemaModule(types: types).ctx
        let ctx = makeKIRContext(
            moduleName: "ThrowingLambdaTest",
            interner: interner,
            sema: sema
        )

        // A pre-ABI `canThrow` bit is not proof the lambda cannot throw: source
        // calls acquire thrown channels later in ABI lowering, and function-value
        // adapters need the closure-object path regardless. The pass must still
        // convert so stored lambdas do not keep the flat capture ABI.
        #expect(pass.shouldRun(module: module, ctx: ctx))
        try pass.run(module: module, ctx: ctx)

        let invokeWrapper = try closureWrapper(for: lambdaSym, in: module)
        let invokeWrapperName = interner.resolve(invokeWrapper.name)
        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "Expected lowered main function.")
        let callees = extractCallees(from: loweredMain.body, interner: interner)
        #expect(callees.contains(RuntimeCall.objectNew.name),
            "Expected closure object allocation via kk_object_new")
        #expect(callees.contains(RuntimeCall.arraySet.name),
            "Expected capture storage via kk_array_set")
        #expect(callees.contains(invokeWrapperName),
            "Expected invoke wrapper \(invokeWrapperName) to be called")
        #expect(!callees.contains(interner.resolve(lambdaName)),
            "Expected direct lambda call to be replaced by closure invoke")

        let rewrittenCall = try #require(loweredMain.body.first {
            if case let .call(_, callee, _, _, _, _, _, _) = $0 { return callee == invokeWrapper.name }
            return false
        })
        if case let .call(_, _, _, _, canThrow, rewrittenThrown, _, _) = rewrittenCall {
            #expect(canThrow)
            #expect(rewrittenThrown == thrownSlot)
        }
    }

    @Test
    func testClosureConversionHandlesMultipleCaptures() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 1)
        let lambdaSym = SymbolID(rawValue: 5)
        let lambdaName = interner.intern("kk_lambda_70")

        let captureParamSym1 = SymbolID(rawValue: -2_000_070)
        let captureParamSym2 = SymbolID(rawValue: -2_000_071)
        let valueParamSym = SymbolID(rawValue: -1_000_070)

        let captureExpr1 = arena.appendExpr(.symbolRef(captureParamSym1), type: intType)
        let captureExpr2 = arena.appendExpr(.symbolRef(captureParamSym2), type: intType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)
        let addResult = arena.appendExpr(.temporary(10), type: intType)
        let bodyResult = arena.appendExpr(.temporary(11), type: intType)

        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: captureParamSym1, type: intType),
                KIRParameter(symbol: captureParamSym2, type: intType),
                KIRParameter(symbol: valueParamSym, type: intType),
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: captureExpr1, value: .symbolRef(captureParamSym1)),
                .constValue(result: captureExpr2, value: .symbolRef(captureParamSym2)),
                .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
                .binary(op: .add, lhs: captureExpr1, rhs: captureExpr2, result: addResult),
                .binary(op: .add, lhs: addResult, rhs: valueExpr, result: bodyResult),
                .returnValue(bodyResult),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        let capturedVal1 = arena.appendExpr(.intLiteral(100), type: intType)
        let capturedVal2 = arena.appendExpr(.intLiteral(200), type: intType)
        let callArg = arena.appendExpr(.intLiteral(7), type: intType)
        let callResult = arena.appendExpr(.temporary(20), type: intType)

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: capturedVal1, value: .intLiteral(100)),
                .constValue(result: capturedVal2, value: .intLiteral(200)),
                .constValue(result: callArg, value: .intLiteral(7)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [capturedVal1, capturedVal2, callArg],
                    result: callResult,
                    canThrow: false
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let sema = makeSemaModule(types: types).ctx
        let ctx = makeKIRContext(
            moduleName: "MultiCaptureTest",
            interner: interner,
            sema: sema
        )

        #expect(pass.shouldRun(module: module, ctx: ctx))
        try pass.run(module: module, ctx: ctx)

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "Expected lowered main function.")

        let callees = extractCallees(from: loweredMain.body, interner: interner)

        #expect(callees.contains(RuntimeCall.objectNew.name),
            "Expected closure object allocation")

        let arraySetCount = callees.filter { $0 == RuntimeCall.arraySet.name }.count
        #expect(arraySetCount == 2,
            "Expected two kk_array_set calls for two captures")

        let wrapper = try closureWrapper(for: lambdaSym, in: module)
        let invokeWrapperName = interner.resolve(wrapper.name)
        #expect(callees.contains(invokeWrapperName),
            "Expected invoke wrapper to be called")

        let wrapperCallees = extractCallees(from: wrapper.body, interner: interner)
        let arrayGetCount = wrapperCallees.filter { $0 == RuntimeCall.arrayGetInbounds.name }.count
        #expect(arrayGetCount == 2,
            "Expected invoke wrapper to load two captures via kk_array_get_inbounds")

        #expect(wrapper.params.count == 2,
            "Expected invoke wrapper to have 2 params (closureObj + 1 value)")
    }

    @Test(arguments: [false, true])
    func testClosureConversionPreservesThrownChannel(hasSourceCall: Bool) throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 1)
        let lambdaSym = SymbolID(rawValue: 6)
        let lambdaName = interner.intern("kk_lambda_80")

        let captureParamSym = SymbolID(rawValue: -2_000_080)
        let valueParamSym = SymbolID(rawValue: -1_000_080)

        let captureExpr = arena.appendExpr(.symbolRef(captureParamSym), type: intType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)

        var lambdaBody: [KIRInstruction] = [
            .beginBlock,
            .constValue(result: captureExpr, value: .symbolRef(captureParamSym)),
            .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
        ]
        let sourceCallee = interner.intern("sourceMethodWithDefaultArguments")
        if hasSourceCall {
            lambdaBody.append(.call(callee: sourceCallee, arguments: [captureExpr], result: nil, canThrow: false))
        }
        lambdaBody.append(.returnValue(captureExpr))
        lambdaBody.append(.endBlock)
        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: captureParamSym, type: intType),
                KIRParameter(symbol: valueParamSym, type: intType),
            ],
            returnType: intType,
            body: lambdaBody,
            isSuspend: false,
            isInline: false
        )

        let capturedValue = arena.appendExpr(.intLiteral(42), type: intType)
        let callArg = arena.appendExpr(.intLiteral(1), type: intType)
        let callResult = arena.appendExpr(.temporary(30), type: intType)

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: capturedValue, value: .intLiteral(42)),
                .constValue(result: callArg, value: .intLiteral(1)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [capturedValue, callArg],
                    result: callResult,
                    canThrow: false
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let sema = makeSemaModule(types: types).ctx
        let ctx = makeKIRContext(
            moduleName: "NonThrowingCalleeTest",
            interner: interner,
            sema: sema
        )

        try pass.run(module: module, ctx: ctx)

        let invokeWrapperName = try closureWrapper(for: lambdaSym, in: module).name
        #expect(!module.nonThrowingClosureCallees.contains(invokeWrapperName))
        #expect(!module.nonThrowingClosureCallees.contains(lambdaName))

        try ABILoweringPass().run(module: module, ctx: ctx)
        let wrapper = try closureWrapper(for: lambdaSym, in: module)
        let wrapperCall = try #require(wrapper.body.first {
            if case let .call(_, callee, _, _, _, _, _, _) = $0 { return callee == lambdaName }
            return false
        })
        if case let .call(_, _, _, _, canThrow, thrownResult, _, _) = wrapperCall {
            #expect(canThrow)
            #expect(thrownResult == nil, "The wrapper must propagate the exception to its caller")
        }
        let caller = try #require(module.arena.declarations.compactMap {
            if case let .function(function) = $0, function.symbol == mainSym { return function }
            return nil
        }.first)
        let callerCall = try #require(caller.body.first {
            if case let .call(_, callee, _, _, _, _, _, _) = $0 { return callee == invokeWrapperName }
            return false
        })
        if case let .call(_, _, _, _, canThrow, _, _, _) = callerCall { #expect(canThrow) }
        if hasSourceCall {
            let loweredLambda = try #require(module.arena.declarations.compactMap {
                if case let .function(function) = $0, function.symbol == lambdaSym { return function }
                return nil
            }.first)
            let sourceCall = try #require(loweredLambda.body.first {
                if case let .call(_, callee, _, _, _, _, _, _) = $0 { return callee == sourceCallee }
                return false
            })
            if case let .call(_, _, _, _, canThrow, _, _, _) = sourceCall { #expect(canThrow) }
        }
    }

    @Test
    func testClosureConversionSkipsZeroValueParamLambdaWithCapture() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 1)
        let lambdaSym = SymbolID(rawValue: 11)
        let lambdaName = interner.intern("kk_lambda_110")

        let captureParamSym = SymbolID(rawValue: -2_000_110)
        let captureExpr = arena.appendExpr(.symbolRef(captureParamSym), type: intType)

        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: captureParamSym, type: intType),
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: captureExpr, value: .symbolRef(captureParamSym)),
                .returnValue(captureExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        let capturedValue = arena.appendExpr(.intLiteral(42), type: intType)
        let callResult = arena.appendExpr(.temporary(30), type: intType)

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: capturedValue, value: .intLiteral(42)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [capturedValue],
                    result: callResult,
                    canThrow: false
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let ctx = makeKIRContext(
            moduleName: "ZeroValueParamTest",
            interner: interner
        )

        #expect(!pass.shouldRun(module: module, ctx: ctx),
            "Expected pass to skip zero-value-param lambda with capture (scope function)")
    }

    @Test
    func testClosureConversionInvokeWrapperPreservesSuspendFlag() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 1)
        let lambdaSym = SymbolID(rawValue: 12)
        let lambdaName = interner.intern("kk_lambda_120")

        let captureParamSym = SymbolID(rawValue: -2_000_120)
        let valueParamSym = SymbolID(rawValue: -1_000_120)

        let captureExpr = arena.appendExpr(.symbolRef(captureParamSym), type: intType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)

        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: captureParamSym, type: intType),
                KIRParameter(symbol: valueParamSym, type: intType),
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: captureExpr, value: .symbolRef(captureParamSym)),
                .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
                .returnValue(valueExpr),
                .endBlock,
            ],
            isSuspend: true,
            isInline: false
        )

        let capturedValue = arena.appendExpr(.intLiteral(11), type: intType)
        let callArg = arena.appendExpr(.intLiteral(22), type: intType)
        let callResult = arena.appendExpr(.temporary(30), type: intType)

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: capturedValue, value: .intLiteral(11)),
                .constValue(result: callArg, value: .intLiteral(22)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [capturedValue, callArg],
                    result: callResult,
                    canThrow: false
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        _ = arena.appendDecl(.function(lambdaFn))
        let mainID = arena.appendDecl(.function(mainFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let sema = makeSemaModule(types: types).ctx
        let ctx = makeKIRContext(
            moduleName: "SuspendFlagTest",
            interner: interner,
            sema: sema
        )

        try pass.run(module: module, ctx: ctx)

        let wrapper = try closureWrapper(for: lambdaSym, in: module)
        #expect(wrapper.isSuspend,
            "Expected invoke wrapper to preserve isSuspend=true from the original lambda")
    }

    @Test
    func testClosureConversionClassIDIsNonZero() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 1)
        let lambdaSym = SymbolID(rawValue: 13)
        let lambdaName = interner.intern("kk_lambda_130")

        let captureParamSym = SymbolID(rawValue: -2_000_130)
        let valueParamSym = SymbolID(rawValue: -1_000_130)

        let captureExpr = arena.appendExpr(.symbolRef(captureParamSym), type: intType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)

        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: captureParamSym, type: intType),
                KIRParameter(symbol: valueParamSym, type: intType),
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: captureExpr, value: .symbolRef(captureParamSym)),
                .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
                .returnValue(valueExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        let capturedValue = arena.appendExpr(.intLiteral(1), type: intType)
        let callArg = arena.appendExpr(.intLiteral(2), type: intType)
        let callResult = arena.appendExpr(.temporary(30), type: intType)

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: capturedValue, value: .intLiteral(1)),
                .constValue(result: callArg, value: .intLiteral(2)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [capturedValue, callArg],
                    result: callResult,
                    canThrow: false
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let sema = makeSemaModule(types: types).ctx
        let ctx = makeKIRContext(
            moduleName: "ClassIDTest",
            interner: interner,
            sema: sema
        )

        try pass.run(module: module, ctx: ctx)

        let loweredMain = try requireTestValue(module.arena.decl(mainID)?.function, "Expected lowered main function.")

        let classIDConstants = loweredMain.body.compactMap { instruction -> Int64? in
            guard case let .constValue(_, value) = instruction,
                  case let .intLiteral(literal) = value,
                  literal > 100
            else { return nil }
            return literal
        }
        #expect(classIDConstants.count == 1,
            "Expected exactly one class ID constant in lowered main")
        if let classID = classIDConstants.first {
            #expect(classID > 0,
                "Expected class ID to be a positive non-zero value")
        }
    }
}
#endif
