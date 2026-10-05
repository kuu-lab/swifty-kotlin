#if canImport(Testing)
@testable import CompilerCore
import Testing

extension LoweringABIAndPropertyRegressionTests {
    @Test(arguments: [
        PrimitiveType.byte, .short, .ubyte, .ushort, .int, .long, .uint, .ulong,
        .float, .double, .char, .boolean,
    ], [false, true])
    func testListGetUnboxesPrimitiveBeforeExtensionCall(primitive: PrimitiveType, hasSymbol: Bool) throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let elementType = types.make(.primitive(primitive, .nonNull))
        let getSymbol = SymbolID(rawValue: 7201)
        if hasSymbol {
            // Indexed access can retain a specialized signature, even though
            // the runtime bridge still returns an erased, boxed element.
            symbols.setFunctionSignature(
                FunctionSignature(parameterTypes: [types.anyType, types.intType], returnType: elementType),
                for: getSymbol
            )
        }
        let list = arena.appendTemporary(type: types.anyType)
        let index = arena.appendExpr(.intLiteral(0), type: types.intType)
        let element = arena.appendTemporary(type: elementType)
        let thrown = arena.appendTemporary(type: types.nullableAnyType)
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 7200), name: interner.intern("main"), params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: hasSymbol ? getSymbol : nil, callee: interner.intern("__kk_list_get"),
                      arguments: [list, index], result: element, canThrow: true, thrownResult: thrown),
                .jumpIfNotNull(value: thrown, target: 1),
                .call(symbol: nil, callee: interner.intern("consumeElement"), arguments: [element],
                      result: nil, canThrow: false, thrownResult: nil),
                .label(1),
                .returnUnit,
            ], isSuspend: false, isInline: false
        )
        let decl = arena.appendDecl(.function(function))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [decl])], arena: arena)
        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        try ABILoweringPass().run(module: module, ctx: makeKIRContext(interner: interner, sema: sema))

        let body = try findKIRFunctionBody(named: "main", in: module, interner: interner)
        guard case let .call(_, getCallee, _, boxed, _, getThrown, _, _) = body[0],
              let boxed,
              case let .jumpIfNotNull(checkedThrown, _) = body[1],
              case let .call(_, unboxCallee, unboxArgs, unboxed, _, _, _, _) = body[2],
              case let .call(_, consumeCallee, consumeArgs, _, _, _, _, _) = body[3]
        else {
            Issue.record("Expected get, exception check, unbox, then extension call")
            return
        }
        #expect(interner.resolve(getCallee) == "__kk_list_get")
        #expect(boxed != element)
        #expect(getThrown == thrown && checkedThrown == thrown)
        let expectedUnbox = BoxingCalleeTable(interner: interner).unboxCallee(
            for: elementType, types: types, requireNonNull: true, preferStaticPrimitive: true
        )
        #expect(expectedUnbox != nil)
        #expect(unboxCallee == expectedUnbox)
        #expect(unboxArgs == [boxed])
        #expect(unboxed == element)
        #expect(interner.resolve(consumeCallee) == "consumeElement")
        #expect(consumeArgs == [element])
        #expect(arena.exprType(element) == elementType)
    }

    @Test
    func testListGetPreservesNullableAndReferenceElements() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let list = arena.appendTemporary(type: types.anyType)
        let index = arena.appendExpr(.intLiteral(0), type: types.intType)
        let results = [types.makeNullable(types.shortType), types.nullableAnyType, types.stringType].map {
            arena.appendTemporary(type: $0)
        }
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 7210), name: interner.intern("main"), params: [],
            returnType: types.unitType,
            body: results.map { result in
                .call(symbol: nil, callee: interner.intern("__kk_list_get"), arguments: [list, index],
                      result: result, canThrow: true, thrownResult: nil)
            } + [.returnUnit], isSuspend: false, isInline: false
        )
        let decl = arena.appendDecl(.function(function))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [decl])], arena: arena)
        let sema = makeSemaModule(types: types).ctx
        try ABILoweringPass().run(module: module, ctx: makeKIRContext(interner: interner, sema: sema))

        let body = try findKIRFunctionBody(named: "main", in: module, interner: interner)
        #expect(extractCallees(from: body, interner: interner) == Array(repeating: "__kk_list_get", count: 3))
    }
}
#endif
