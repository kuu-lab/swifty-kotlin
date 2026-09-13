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

        let targetName = interner.intern("__kk_set_contains")

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
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(
            !callees.contains("kk_unbox_bool"),
            "Expected no kk_unbox_bool for raw-Boolean callee __kk_set_contains, got: \(callees)"
        )
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
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(
            callees.contains("kk_unbox_bool"),
            "Expected kk_unbox_bool for Boolean-returning callee outside the raw-Boolean spec set, got: \(callees)"
        )
    }
}
#endif
