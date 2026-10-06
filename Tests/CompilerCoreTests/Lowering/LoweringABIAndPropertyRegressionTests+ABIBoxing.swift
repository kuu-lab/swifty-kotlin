#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LoweringABIAndPropertyRegressionTests {
    // MARK: - ABI Boxing/Unboxing Tests

    @Test(arguments: [PrimitiveType.int, .long, .uint, .ulong])
    func testABILoweringUnboxesGenericPrimitiveReceiver(primitive: PrimitiveType) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let primitiveType = types.make(.primitive(primitive, .nonNull))
        let typeParamSymbol = SymbolID(rawValue: 2900)
        let genericType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol)))
        symbols.setTypeParameterUpperBounds([primitiveType], for: typeParamSymbol)

        let receiverTypes = [genericType, primitiveType]
        let targetTypes = [primitiveType, genericType, types.makeNullable(primitiveType)]
        for receiverType in receiverTypes {
            for targetType in targetTypes {
                let arena = KIRArena()
                let receiverSymbol = SymbolID(rawValue: 2901)
                let targetSymbol = SymbolID(rawValue: 2902)
                let targetName = interner.intern("receiverCall")
                symbols.setFunctionSignature(
                    FunctionSignature(receiverType: targetType, parameterTypes: [types.intType], returnType: types.unitType),
                    for: targetSymbol
                )
                let receiver = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
                let argument = arena.appendExpr(.intLiteral(7), type: types.intType)
                let callerID = arena.appendDecl(.function(KIRFunction(
                    symbol: SymbolID(rawValue: 2903),
                    name: interner.intern("caller"),
                    params: [KIRParameter(symbol: receiverSymbol, type: receiverType)],
                    returnType: types.unitType,
                    body: [
                        .call(symbol: targetSymbol, callee: targetName, arguments: [receiver, argument], result: nil, canThrow: false, thrownResult: nil),
                        .returnUnit,
                    ],
                    isSuspend: false,
                    isInline: false
                )))
                let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)
                let sema = makeSemaModule(symbols: symbols, types: types).ctx
                try runLowering(module: module, interner: interner, moduleName: "ABIReceiver", sema: sema)

                let lowered = try findKIRFunction(named: "caller", in: module, interner: interner)
                let shouldUnbox = receiverType == genericType && targetType == primitiveType
                let targetCallIndex = try #require(lowered.body.firstIndex { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return callee == targetName
                    }
                    return false
                })
                guard case let .call(_, _, arguments, _, _, _, _, _) = lowered.body[targetCallIndex] else {
                    Issue.record("Expected receiver call")
                    continue
                }
                #expect(arguments[1] == argument, "Value parameter must not shift with receiver normalization")
                if shouldUnbox {
                    #expect(arguments[0] != receiver)
                    #expect(arena.exprType(arguments[0]) == primitiveType)
                    let unboxIndex = try #require(lowered.body.firstIndex { instruction in
                        if case let .call(_, _, args, result, canThrow, thrownResult, _, _) = instruction {
                            return args == [receiver] && result == arguments[0] && !canThrow && thrownResult == nil
                        }
                        return false
                    })
                    #expect(unboxIndex < targetCallIndex)
                    let expectedUnbox = try #require(BoxingCalleeTable(interner: interner).unboxCallee(
                        for: types.kind(of: primitiveType), requireNonNull: true, preferStaticPrimitive: true
                    ))
                    guard case let .call(_, callee, _, _, _, _, _, _) = lowered.body[unboxIndex] else { continue }
                    #expect(callee == expectedUnbox)
                } else {
                    #expect(arguments[0] == receiver, "Raw, generic and nullable receivers must retain their representation")
                    #expect(targetCallIndex == 0)
                }
            }
        }
    }

    @Test
    func testABILoweringBoxesIntArgumentForAnyParameter() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let callerSym = SymbolID(rawValue: 3000)
        let targetSym = SymbolID(rawValue: 3001)
        let targetParamSym = SymbolID(rawValue: 3002)

        let targetName = interner.intern("acceptAny")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [anyNullableType], returnType: types.unitType, valueParameterSymbols: [targetParamSym]),
            for: targetSym
        )

        let argExpr = arena.appendExpr(.intLiteral(42), type: intType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [KIRParameter(symbol: targetParamSym, type: anyNullableType)],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "ABIBoxInt", sema: sema)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(callees.contains("kk_box_int_static"), "Expected kk_box_int_static call for Int -> Any? boxing, got: \(callees)")
    }

    @Test
    func testABILoweringBoxesBoolArgumentForAnyParameter() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let boolType = types.make(.primitive(.boolean, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let callerSym = SymbolID(rawValue: 3100)
        let targetSym = SymbolID(rawValue: 3101)
        let targetParamSym = SymbolID(rawValue: 3102)

        let targetName = interner.intern("acceptAny")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [anyNullableType], returnType: types.unitType, valueParameterSymbols: [targetParamSym]),
            for: targetSym
        )

        let argExpr = arena.appendExpr(.boolLiteral(true), type: boolType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [KIRParameter(symbol: targetParamSym, type: anyNullableType)],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "ABIBoxBool", sema: sema)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(callees.contains("kk_box_bool_static"), "Expected kk_box_bool_static call for Bool -> Any? boxing, got: \(callees)")
    }

    @Test
    func testABILoweringBoxesIntToNullableIntParameter() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))

        let callerSym = SymbolID(rawValue: 3200)
        let targetSym = SymbolID(rawValue: 3201)
        let targetParamSym = SymbolID(rawValue: 3202)

        let targetName = interner.intern("acceptNullableInt")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [nullableIntType], returnType: types.unitType, valueParameterSymbols: [targetParamSym]),
            for: targetSym
        )

        let argExpr = arena.appendExpr(.intLiteral(7), type: intType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [KIRParameter(symbol: targetParamSym, type: nullableIntType)],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "ABIBoxNullableInt", sema: sema)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(callees.contains("kk_box_int_static"), "Expected kk_box_int_static call for Int -> Int? boxing, got: \(callees)")
    }

    @Test
    func testABILoweringUnboxesAnyReturnToIntResult() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let callerSym = SymbolID(rawValue: 3300)
        let targetSym = SymbolID(rawValue: 3301)

        let targetName = interner.intern("getAny")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: anyNullableType),
            for: targetSym
        )

        let resultExpr = arena.appendExpr(.temporary(0), type: intType)

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
            returnType: anyNullableType,
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
        try runLowering(module: module, interner: interner, moduleName: "ABIUnboxAny", sema: sema)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(callees.contains("kk_unbox_int_static"), "Expected kk_unbox_int_static call for Any? -> Int unboxing, got: \(callees)")
    }

    @Test
    func testABILoweringUnboxesNullableIntReturnToNonNullInt() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))

        let callerSym = SymbolID(rawValue: 3400)
        let targetSym = SymbolID(rawValue: 3401)

        let targetName = interner.intern("getNullableInt")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: nullableIntType),
            for: targetSym
        )

        let resultExpr = arena.appendExpr(.temporary(0), type: intType)

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
            returnType: nullableIntType,
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
        try runLowering(module: module, interner: interner, moduleName: "ABIUnboxNullableInt", sema: sema)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(callees.contains("kk_unbox_int_static"), "Expected kk_unbox_int_static call for Int? -> Int unboxing, got: \(callees)")
    }

    @Test
    func testABILoweringBoxesReturnValueWhenFunctionReturnsAny() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let fnSym = SymbolID(rawValue: 3500)
        let valueExpr = arena.appendExpr(.intLiteral(42), type: intType)

        let function = KIRFunction(
            symbol: fnSym,
            name: interner.intern("returnBoxed"),
            params: [],
            returnType: anyNullableType,
            body: [
                .returnValue(valueExpr),
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(function))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = makeSemaModule(types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "ABIBoxReturn", sema: sema)

        let lowered = try findKIRFunction(named: "returnBoxed", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(callees.contains("kk_box_int_static"), "Expected kk_box_int_static before returnValue for Any? return type, got: \(callees)")
    }

    @Test
    func testABILoweringBoxesCopyFromIntToAnySlot() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let fnSym = SymbolID(rawValue: 3600)
        let fromExpr = arena.appendExpr(.intLiteral(10), type: intType)
        let toExpr = arena.appendExpr(.temporary(1), type: anyNullableType)

        let function = KIRFunction(
            symbol: fnSym,
            name: interner.intern("copyBoxed"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(function))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = makeSemaModule(types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "ABICopyBox", sema: sema)

        let lowered = try findKIRFunction(named: "copyBoxed", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(callees.contains("kk_box_int_static"), "Expected kk_box_int_static for copy Int -> Any?, got: \(callees)")
        // Verify that the copy instruction was replaced (no copy should remain)
        let hasCopy = lowered.body.contains { instruction in
            if case .copy = instruction { return true }
            return false
        }
        #expect(!hasCopy, "Expected copy to be replaced with boxing call")
    }

    @Test
    func testABILoweringUnboxesCopyFromAnyToIntSlot() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let fnSym = SymbolID(rawValue: 3700)
        let fromExpr = arena.appendExpr(.temporary(0), type: anyNullableType)
        let toExpr = arena.appendExpr(.temporary(1), type: intType)

        let function = KIRFunction(
            symbol: fnSym,
            name: interner.intern("copyUnboxed"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(function))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = makeSemaModule(types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "ABICopyUnbox", sema: sema)

        let lowered = try findKIRFunction(named: "copyUnboxed", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(callees.contains("kk_unbox_int_static"), "Expected kk_unbox_int_static for copy Any? -> Int, got: \(callees)")
        // Verify that the copy instruction was replaced
        let hasCopy = lowered.body.contains { instruction in
            if case .copy = instruction { return true }
            return false
        }
        #expect(!hasCopy, "Expected copy to be replaced with unboxing call")
    }
}
#endif
