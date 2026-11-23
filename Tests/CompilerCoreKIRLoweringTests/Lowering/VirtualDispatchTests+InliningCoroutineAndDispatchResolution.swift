#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

extension VirtualDispatchTests {

    @Test func testInlineLoweringResolvesAliasesInVirtualCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let anyType = types.anyType

        let inlineSym = SymbolID(rawValue: 6000)
        let callerSym = SymbolID(rawValue: 6001)
        let virtualMethodSym = SymbolID(rawValue: 6002)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: types.unitType,
                valueParameterSymbols: []
            ),
            for: virtualMethodSym
        )

        let inlineParamSym = SymbolID(rawValue: 6003)
        let paramExpr = arena.appendExpr(.symbolRef(inlineParamSym), type: anyType)
        let vcResult = arena.appendExpr(.temporary(10), type: types.unitType)

        let inlineFn = KIRFunction(
            symbol: inlineSym,
            name: interner.intern("inlineHelper"),
            params: [KIRParameter(symbol: inlineParamSym, type: anyType)],
            returnType: types.unitType,
            body: [
                .virtualCall(
                    symbol: virtualMethodSym,
                    callee: interner.intern("virtualMethod"),
                    receiver: paramExpr,
                    arguments: [],
                    result: vcResult,
                    canThrow: false,
                    dispatch: .vtable(slot: 1)
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: true
        )

        let callerArgExpr = arena.appendExpr(.temporary(20), type: anyType)
        let callResult = arena.appendExpr(.temporary(21), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("caller"),
            params: [KIRParameter(symbol: SymbolID(rawValue: 6004), type: anyType)],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: inlineSym,
                    callee: interner.intern("inlineHelper"),
                    arguments: [callerArgExpr],
                    result: callResult,
                    canThrow: false
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(inlineFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "InlineVirtual", sema: sema)

        let lowered = try findKIRFunction(named: "caller", in: module, interner: interner)
        let hasVirtualCall = lowered.body.contains { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }
        #expect(hasVirtualCall, "After inlining, caller should contain the virtualCall from the inlined function body. Body: \(lowered.body)")

        let vcInstruction = lowered.body.first { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }
        guard case let .virtualCall(_, _, _, _, _, _, _, dispatch) = vcInstruction else {
            Issue.record("Expected virtualCall instruction")
            return
        }
        #expect(dispatch == .vtable(slot: 1), "Dispatch kind should be preserved after inlining")
    }

    @Test func testRegularCallInstructionNotAffectedByVirtualCallChanges() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let callerSym = SymbolID(rawValue: 7000)
        let targetSym = SymbolID(rawValue: 7001)
        let targetParamSym = SymbolID(rawValue: 7002)

        let targetName = interner.intern("regularFunction")
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.anyType],
                returnType: types.unitType,
                valueParameterSymbols: [targetParamSym]
            ),
            for: targetSym
        )

        let argExpr = arena.appendExpr(.temporary(0), type: types.anyType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: targetSym,
                    callee: targetName,
                    arguments: [argExpr],
                    result: resultExpr,
                    canThrow: false
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [KIRParameter(symbol: targetParamSym, type: types.anyType)],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "RegularCall", sema: sema)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(callees.contains("regularFunction"), "Regular .call should still work after virtual dispatch changes")
        let hasVirtualCall = lowered.body.contains { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }
        #expect(!hasVirtualCall, "Regular .call should not become virtualCall")
    }

    @Test func testInlineLoweringDoesNotRedirectKnownUnmatchedSymbolByName() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let anyType = types.anyType
        let calleeName = interner.intern("iterator")

        let unresolvedIteratorSym = SymbolID(rawValue: 8000)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: anyType, valueParameterSymbols: []),
            for: unresolvedIteratorSym
        )

        let callResult = arena.appendExpr(.temporary(0), type: anyType)
        let callerFn = KIRFunction(
            symbol: SymbolID(rawValue: 8001),
            name: interner.intern("caller"),
            params: [],
            returnType: anyType,
            body: [
                .call(
                    symbol: unresolvedIteratorSym,
                    callee: calleeName,
                    arguments: [],
                    result: callResult,
                    canThrow: false
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let markerResult = arena.appendExpr(.temporary(1), type: anyType)
        let unrelatedIteratorFn = KIRFunction(
            symbol: SymbolID(rawValue: 8002),
            name: calleeName,
            params: [],
            returnType: anyType,
            body: [
                .call(
                    callee: interner.intern("unrelatedIteratorFixtureMarker"),
                    arguments: [],
                    result: markerResult,
                    canThrow: false
                ),
                .returnValue(markerResult),
            ],
            isSuspend: false,
            isInline: true
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(unrelatedIteratorFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "ByNameFallbackRegression", sema: sema)

        let lowered = try findKIRFunction(named: "caller", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(
            !callees.contains("unrelatedIteratorFixtureMarker"),
            "A call with a known-but-unmatched symbol must not be spliced with an unrelated same-named bundled inline function's body. Body: \(lowered.body)"
        )
        #expect(
            callees.contains("iterator"),
            "The original call should be left untouched for its own resolution mechanism to handle. Body: \(lowered.body)"
        )
    }

    @Test func testCoroutineLoweringExtractCallInfoForVirtualCall() {
        let arena = KIRArena()
        let types = TypeSystem()
        let receiverExpr = arena.appendExpr(.temporary(0), type: types.anyType)
        let argExpr = arena.appendExpr(.temporary(1), type: types.anyType)
        let resultExpr = arena.appendExpr(.temporary(2), type: types.unitType)

        let instruction = KIRInstruction.virtualCall(
            symbol: SymbolID(rawValue: 100),
            callee: InternedString(rawValue: 5),
            receiver: receiverExpr,
            arguments: [argExpr],
            result: resultExpr,
            canThrow: true,
            dispatch: .vtable(slot: 2)
        )

        let pass = CoroutineLoweringPass()
        let callInfo = pass.extractCallInfo(instruction)

        #expect(callInfo != nil, "extractCallInfo should return non-nil for virtualCall")
        #expect(callInfo?.symbol == SymbolID(rawValue: 100))
        #expect(callInfo?.callee == InternedString(rawValue: 5))
        #expect(callInfo?.result == resultExpr)
        #expect(callInfo?.canThrow == true)
        #expect(callInfo?.isVirtual == true)
        #expect(callInfo?.arguments.count == 1, "extractCallInfo arguments should not include receiver")
        #expect(callInfo?.arguments.first == argExpr)
    }

    @Test func testCoroutineLoweringExtractCallInfoForRegularCall() {
        let arena = KIRArena()
        let types = TypeSystem()
        let argExpr = arena.appendExpr(.temporary(0), type: types.anyType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let instruction = KIRInstruction.call(
            symbol: SymbolID(rawValue: 200),
            callee: InternedString(rawValue: 10),
            arguments: [argExpr],
            result: resultExpr,
            canThrow: false
        )

        let pass = CoroutineLoweringPass()
        let callInfo = pass.extractCallInfo(instruction)

        #expect(callInfo != nil, "extractCallInfo should return non-nil for regular call")
        #expect(callInfo?.isVirtual == false)
        #expect(callInfo?.arguments.count == 1)
    }

    @Test func testCoroutineLoweringExtractCallInfoReturnsNilForNonCall() {
        let pass = CoroutineLoweringPass()
        let callInfo = pass.extractCallInfo(.returnUnit)
        #expect(callInfo == nil, "extractCallInfo should return nil for non-call instruction")
    }

    @Test func testCoroutineLoweringEmitsVirtualCallForVirtualSuspendFunction() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let anyType = types.anyType

        let outerSuspendSym = symbols.define(
            kind: .function,
            name: interner.intern("outerSuspend"),
            fqName: [interner.intern("outerSuspend")],
            declSite: nil,
            visibility: .public
        )
        let innerVirtualSym = symbols.define(
            kind: .function,
            name: interner.intern("innerVirtual"),
            fqName: [interner.intern("innerVirtual")],
            declSite: nil,
            visibility: .public
        )

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: anyType,
                valueParameterSymbols: []
            ),
            for: innerVirtualSym
        )

        let receiverExpr = arena.appendExpr(.temporary(0), type: anyType)
        let callResult = arena.appendExpr(.temporary(1), type: anyType)

        let outerSuspendFn = KIRFunction(
            symbol: outerSuspendSym,
            name: interner.intern("outerSuspend"),
            params: [],
            returnType: anyType,
            body: [
                .virtualCall(
                    symbol: innerVirtualSym,
                    callee: interner.intern("innerVirtual"),
                    receiver: receiverExpr,
                    arguments: [],
                    result: callResult,
                    canThrow: false,
                    dispatch: .vtable(slot: 0)
                ),
                .returnValue(callResult),
            ],
            isSuspend: true,
            isInline: false
        )

        let mainSym = symbols.define(
            kind: .function,
            name: interner.intern("main"),
            fqName: [interner.intern("main")],
            declSite: nil,
            visibility: .public
        )

        let mainResult = arena.appendExpr(.temporary(10), type: anyType)
        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: outerSuspendSym,
                    callee: interner.intern("outerSuspend"),
                    arguments: [],
                    result: mainResult,
                    canThrow: false
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        let outerID = arena.appendDecl(.function(outerSuspendFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID, outerID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "VirtualSuspend", sema: sema)

        let allFunctions = findAllKIRFunctions(in: module)
        let wrapper = try #require(allFunctions.first { $0.symbol == outerSuspendSym })
        let suspendFunction = try LoweringTestRuntime.loweredSuspendFunction(for: wrapper, in: module, interner: interner)
        let hasVirtualCall = suspendFunction.body.contains { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }
        #expect(hasVirtualCall, "Coroutine state machine should emit virtualCall for virtual suspend calls, not .call. Body callees: \(suspendFunction.body)")
    }

    @Test func testSuspendCallableRefVirtualDispatchUsesWrapperABI() throws {
        let source = """
        interface Writer { suspend fun flush(): Int }
        class BufferedWriter : Writer { override suspend fun flush(): Int = 42 }
        fun Writer.flushLater(): suspend () -> Int = ::flush
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let virtualFlushCalls = findAllKIRFunctions(in: module).flatMap { function in
            function.body.compactMap { instruction -> [KIRExprID]? in
                guard case let .virtualCall(_, callee, _, arguments, _, _, _, _) = instruction,
                      callee == ctx.interner.intern("flush")
                else { return nil }
                return arguments
            }
        }
        #expect(!virtualFlushCalls.isEmpty)
        #expect(virtualFlushCalls.allSatisfy { $0.isEmpty },
                "Virtual suspend calls use the original blocking wrapper's explicit arguments.")
    }

}
#endif
