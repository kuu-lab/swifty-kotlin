#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

extension LoweringABIAndPropertyRegressionTests {
    // MARK: - ABI Boxing/Unboxing Tests

    @Test(arguments: ["__kk_set_contains", "__kk_map_get", "__kk_mutable_set_remove", "__kk_mutable_map_remove"])
    func enumLookupKeysUseInsertionBoxing(callee: String) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let name = interner.intern("Kind")
        let owner = symbols.define(kind: .enumClass, name: name, fqName: [name],
                                   declSite: nil, visibility: .public, flags: [])
        let enumType = types.make(.classType(ClassType(classSymbol: owner, args: [], nullability: .nonNull)))
        let pass = ABILoweringPass()
        let table = BoxingCalleeTable(interner: interner)
        let boxed = pass.boxingCallee(
            argType: enumType, paramType: types.anyType, callee: interner.intern(callee),
            types: types, interner: interner, boxingCalleeTable: table, symbols: symbols,
            boxTypeParamBoundary: true
        )
        let insertion = pass.boxingCallee(
            argType: enumType, paramType: types.anyType, callee: interner.intern("__kk_mutable_set_add"),
            types: types, interner: interner, boxingCalleeTable: table, symbols: symbols,
            boxTypeParamBoundary: true
        )
        #expect(boxed != nil)
        #expect(boxed == insertion)
    }

    @Test(arguments: [PrimitiveType.int, .long, .uint, .ulong, .float, .double], [false, true])
    func testABILoweringUnboxesErasedPrimitiveCallSlot(primitive: PrimitiveType, isReceiver: Bool) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let primitiveType = types.make(.primitive(primitive, .nonNull))
        let typeParamSymbol = SymbolID(rawValue: 2900)
        let genericType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol)))
        symbols.setTypeParameterUpperBounds([primitiveType], for: typeParamSymbol)

        let receiverTypes = [genericType, types.anyType, types.nullableAnyType,
                             types.makeNullable(primitiveType), primitiveType]
        let targetTypes = isReceiver
            ? [primitiveType, genericType, types.makeNullable(primitiveType)] : [primitiveType]
        for receiverType in receiverTypes {
            for targetType in targetTypes {
                let arena = KIRArena()
                let receiverSymbol = SymbolID(rawValue: 2901)
                let targetSymbol = SymbolID(rawValue: 2902)
                let targetName = interner.intern("receiverCall")
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: isReceiver ? targetType : nil,
                        parameterTypes: isReceiver ? [types.intType] : [targetType, types.intType],
                        returnType: types.unitType
                    ),
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
                        .call(symbol: targetSymbol, callee: targetName, arguments: [receiver, argument], result: nil, canThrow: false),
                        .returnUnit,
                    ],
                    isSuspend: false,
                    isInline: false
                )))
                let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)
                let sema = makeSemaModule(symbols: symbols, types: types).ctx
                try runLowering(module: module, interner: interner, moduleName: "ABIReceiver", sema: sema)

                let lowered = try findKIRFunction(named: "caller", in: module, interner: interner)
                let shouldUnbox = receiverType != primitiveType && targetType == primitiveType
                // KUU-2939: a `.typeParam` receiver slot is the same erased
                // Any boundary as a type-parameter value argument, so the
                // floating-point arguments that always box at that boundary
                // (-0.0 is bit-identical to the null sentinel) box here too.
                let shouldBoxReceiver = receiverType == primitiveType && targetType == genericType
                    && (primitive == .float || primitive == .double)
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
                    let expectedUnbox = try loweringBoxingABI(.unbox, for: primitive, nonNull: true, staticPrimitive: true)
                    guard case let .call(_, callee, _, _, _, _, _, _) = lowered.body[unboxIndex] else { continue }
                    #expect(callee == interner.intern(expectedUnbox.name))
                } else if shouldBoxReceiver {
                    #expect(arguments[0] != receiver)
                    let boxIndex = try #require(lowered.body.firstIndex { instruction in
                        if case let .call(_, _, args, result, canThrow, thrownResult, _, _) = instruction {
                            return args == [receiver] && result == arguments[0] && !canThrow && thrownResult == nil
                        }
                        return false
                    })
                    #expect(boxIndex < targetCallIndex)
                    // A provably non-null Double uses the `_nonnull` box
                    // variant (raw -0.0 is the null sentinel); Float has no
                    // override and keeps the plain static callee.
                    let expectedBox = try loweringBoxingABI(
                        .box, for: primitive, nonNull: primitive == .double, staticPrimitive: true
                    )
                    guard case let .call(_, callee, _, _, _, _, _, _) = lowered.body[boxIndex] else { continue }
                    #expect(callee == interner.intern(expectedBox.name))
                } else {
                    #expect(arguments[0] == receiver, "Raw, generic and nullable slots must retain their representation")
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
                .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false),
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
        let abi = try loweringBoxingABI(.box, for: .int, nonNull: true, staticPrimitive: true)
        let conversion = try requireLoweringRuntimeCall(abi, in: lowered.body, interner: interner)
        #expect(conversion.arguments == [argExpr])
        let boxed = try #require(conversion.result)
        let targetCall = try #require(loweringCalls(in: lowered.body).first { $0.symbol == targetSym })
        #expect(targetCall.arguments == [boxed])
        #expect(boxed != argExpr)
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
                .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false),
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
        let abi = try loweringBoxingABI(.box, for: .boolean, nonNull: true, staticPrimitive: true)
        let conversion = try requireLoweringRuntimeCall(abi, in: lowered.body, interner: interner)
        #expect(conversion.arguments == [argExpr])
        let boxed = try #require(conversion.result)
        let targetCall = try #require(loweringCalls(in: lowered.body).first { $0.symbol == targetSym })
        #expect(targetCall.arguments == [boxed])
        #expect(boxed != argExpr)
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
                .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false),
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
        let abi = try loweringBoxingABI(.box, for: .int, nonNull: true, staticPrimitive: true)
        let conversion = try requireLoweringRuntimeCall(abi, in: lowered.body, interner: interner)
        #expect(conversion.arguments == [argExpr])
        let boxed = try #require(conversion.result)
        let targetCall = try #require(loweringCalls(in: lowered.body).first { $0.symbol == targetSym })
        #expect(targetCall.arguments == [boxed])
        #expect(boxed != argExpr)
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
                .call(symbol: targetSym, callee: targetName, arguments: [], result: resultExpr, canThrow: false),
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
        let abi = try loweringBoxingABI(.unbox, for: .int, nonNull: true, staticPrimitive: true)
        let conversion = try requireLoweringRuntimeCall(abi, in: lowered.body, interner: interner)
        let targetCall = try #require(loweringCalls(in: lowered.body).first { $0.symbol == targetSym })
        let boxed = try #require(targetCall.result)
        #expect(conversion.arguments == [boxed])
        #expect(conversion.result == resultExpr)
        #expect(boxed != resultExpr)
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
                .call(symbol: targetSym, callee: targetName, arguments: [], result: resultExpr, canThrow: false),
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
        let abi = try loweringBoxingABI(.unbox, for: .int, nonNull: true, staticPrimitive: true)
        let conversion = try requireLoweringRuntimeCall(abi, in: lowered.body, interner: interner)
        let targetCall = try #require(loweringCalls(in: lowered.body).first { $0.symbol == targetSym })
        let boxed = try #require(targetCall.result)
        #expect(conversion.arguments == [boxed])
        #expect(conversion.result == resultExpr)
        #expect(boxed != resultExpr)
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
        let abi = try loweringBoxingABI(.box, for: .int, nonNull: true, staticPrimitive: true)
        let conversion = try requireLoweringRuntimeCall(abi, in: lowered.body, interner: interner)
        #expect(conversion.arguments == [valueExpr])
        let boxed = try #require(conversion.result)
        #expect(lowered.body.contains(.returnValue(boxed)))
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
        let abi = try loweringBoxingABI(.box, for: .int, nonNull: true, staticPrimitive: true)
        let conversion = try requireLoweringRuntimeCall(abi, in: lowered.body, interner: interner)
        #expect(conversion.arguments == [fromExpr])
        #expect(conversion.result == toExpr)
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
        let abi = try loweringBoxingABI(.unbox, for: .int, nonNull: true, staticPrimitive: true)
        let conversion = try requireLoweringRuntimeCall(abi, in: lowered.body, interner: interner)
        #expect(conversion.arguments == [fromExpr])
        #expect(conversion.result == toExpr)
        // Verify that the copy instruction was replaced
        let hasCopy = lowered.body.contains { instruction in
            if case .copy = instruction { return true }
            return false
        }
        #expect(!hasCopy, "Expected copy to be replaced with unboxing call")
    }

    @Test
    func localFunctionCapturesDoNotShiftParameterBoxing() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let arena = KIRArena()

        let innerSym = symbols.define(
            kind: .function,
            name: interner.intern("inner"),
            fqName: [interner.intern("inner")],
            declSite: nil,
            visibility: .private,
            flags: [.localFunction]
        )
        let intArraySym = symbols.define(
            kind: .class,
            name: interner.intern("IntArray"),
            fqName: [interner.intern("kotlin"), interner.intern("IntArray")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let intArrayType = types.make(.classType(ClassType(classSymbol: intArraySym, args: [], nullability: .nonNull)))
        let innerSig = FunctionSignature(
            parameterTypes: [types.intType, intArrayType],
            returnType: types.unitType
        )
        symbols.setFunctionSignature(innerSig, for: innerSym)

        let capParamSym = SymbolID(rawValue: 9001)
        let kParamSym = SymbolID(rawValue: 9002)
        let cParamSym = SymbolID(rawValue: 9003)
        let innerFunc = KIRFunction(
            symbol: innerSym,
            name: interner.intern("inner"),
            params: [
                KIRParameter(symbol: capParamSym, type: types.intType),
                KIRParameter(symbol: kParamSym, type: types.intType),
                KIRParameter(symbol: cParamSym, type: intArrayType),
            ],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        let innerDeclID = arena.appendDecl(.function(innerFunc))

        let callerSym = symbols.define(
            kind: .function,
            name: interner.intern("caller"),
            fqName: [interner.intern("caller")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let capExpr = arena.appendExpr(.intLiteral(4), type: types.intType)
        let kExpr = arena.appendExpr(.intLiteral(1), type: types.intType)
        let cExpr = arena.appendExpr(.symbolRef(SymbolID(rawValue: 9004)), type: intArrayType)
        let callResult = arena.appendExpr(.unit, type: types.unitType)

        let callerFunc = KIRFunction(
            symbol: callerSym,
            name: interner.intern("caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: capExpr, value: .intLiteral(4)),
                .constValue(result: kExpr, value: .intLiteral(1)),
                .call(
                    symbol: innerSym,
                    callee: interner.intern("inner"),
                    arguments: [capExpr, kExpr, cExpr],
                    result: callResult,
                    canThrow: false
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let callerDeclID = arena.appendDecl(.function(callerFunc))

        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [innerDeclID, callerDeclID])], arena: arena)
        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "LocalFunCaptureBoxingTest", sema: sema)

        let lowered = try findKIRFunction(named: "caller", in: module, interner: interner)
        // Check that the call to inner has [capExpr, kExpr, cExpr] and kExpr was not boxed
        var foundInnerCall = false
        for instruction in lowered.body {
            if case let .call(sym, _, arguments, _, _, _, _, _) = instruction, sym == innerSym {
                foundInnerCall = true
                #expect(arguments == [capExpr, kExpr, cExpr])
            }
        }
        #expect(foundInnerCall, "Expected to find lowered call to inner")
    }

    // KUU-2939: a `.typeParam` extension receiver is erased exactly like a
    // type-parameter value argument, so a primitive receiver argument must be
    // boxed or the callee reads its raw word as an Any pointer
    // (`'c'.myToString()` rendering `99` instead of `c`).
    @Test
    func testABILoweringBoxesPrimitiveExtensionReceiverForTypeParam() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let charType = types.make(.primitive(.char, .nonNull))
        let typeParamSymbol = SymbolID(rawValue: 3700)
        let genericType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol)))

        // A `declSite` marks the callee Kotlin source-backed, so the generic
        // ABI applies (`isKotlinSourceCallee` / `boxTypeParamArguments`).
        let targetName = interner.intern("ext")
        let targetSym = symbols.define(
            kind: .function,
            name: targetName,
            fqName: [targetName],
            declSite: SourceRange(
                start: SourceLocation(file: FileID(rawValue: 0), offset: 0),
                end: SourceLocation(file: FileID(rawValue: 0), offset: 1)
            ),
            visibility: .public
        )
        symbols.setFunctionSignature(
            FunctionSignature(receiverType: genericType, parameterTypes: [], returnType: types.unitType),
            for: targetSym
        )

        let receiverExpr = arena.appendExpr(.charLiteral(99), type: charType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: SymbolID(rawValue: 3701),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [receiverExpr], result: resultExpr, canThrow: false),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let callerID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try runLowering(module: module, interner: interner, moduleName: "ABIBoxTypeParamReceiver", sema: sema)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let abi = try loweringBoxingABI(.box, for: .char, staticPrimitive: true)
        let conversion = try requireLoweringRuntimeCall(abi, in: lowered.body, interner: interner)
        #expect(conversion.arguments == [receiverExpr])
        let boxed = try #require(conversion.result)
        let targetCall = try #require(loweringCalls(in: lowered.body).first { $0.symbol == targetSym })
        #expect(targetCall.arguments == [boxed])
        #expect(boxed != receiverExpr)
    }
}
#endif

