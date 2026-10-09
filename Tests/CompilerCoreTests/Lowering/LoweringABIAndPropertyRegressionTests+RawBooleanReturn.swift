#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LoweringABIAndPropertyRegressionTests {
    // MARK: - Raw Boolean Return Callees

    @Test
    func testABILoweringSkipsUnboxForRawBooleanReturnCallee() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let boolType = types.make(.primitive(.boolean, .nonNull))

        let callerSym = SymbolID(rawValue: 7100)
        let targetSym = SymbolID(rawValue: 7101)

        let rawBooleanABI = try loweringRuntimeABI("set_contains")
        #expect(rawBooleanABI.returnsRawBoolean)
        let targetName = interner.intern(rawBooleanABI.name)

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: boolType),
            for: targetSym
        )

        let resultExpr = arena.appendExpr(.temporary(0), type: boolType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [],
            returnType: boolType,
            // .returnUnit is intentional – this is a stub for testing caller-side
            // ABI instrumentation (box/unbox insertion); callee body is not under test.
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "ABIRawBool", sema: sema)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let calls = loweringCalls(in: lowered.body)
        #expect(calls.count == 1, "A raw Boolean result must not insert any unboxing call")
        #expect(calls.first?.symbol == targetSym)
        #expect(calls.first?.callee == targetName)
        #expect(calls.first?.result == resultExpr)
    }

    @Test
    func testABILoweringUnboxesBooleanReturnForNonSpecCallee() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let boolType = types.make(.primitive(.boolean, .nonNull))

        let callerSym = SymbolID(rawValue: 7200)
        let targetSym = SymbolID(rawValue: 7201)

        let targetName = interner.intern("acceptAndReturnBool")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: boolType),
            for: targetSym
        )

        let resultExpr = arena.appendExpr(.temporary(0), type: boolType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [],
            returnType: boolType,
            // .returnUnit is intentional – this is a stub for testing caller-side
            // ABI instrumentation (box/unbox insertion); callee body is not under test.
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "ABIBoxedBool", sema: sema)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let abi = try loweringBoxingABI(.unbox, for: .boolean, nonNull: true, staticPrimitive: true)
        let unboxing = try requireLoweringRuntimeCall(abi, in: lowered.body, interner: interner)
        let targetCall = try #require(loweringCalls(in: lowered.body).first { $0.symbol == targetSym })
        let boxed = try #require(targetCall.result)
        #expect(unboxing.arguments == [boxed])
        #expect(unboxing.result == resultExpr)
        #expect(boxed != resultExpr)
    }
}
#endif
