#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension LoweringABIAndPropertyRegressionTests {
    @Test(arguments: [PrimitiveType.float, .double])
    func testABILoweringUnboxesErasedFloatingReturn(primitive: PrimitiveType) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let primitiveType = types.make(.primitive(primitive, .nonNull))
        let genericType = types.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 2920))))
        for sourceType in [types.anyType, types.nullableAnyType, genericType,
                           types.makeNullable(primitiveType), primitiveType] {
            let arena = KIRArena()
            let sourceSymbol = SymbolID(rawValue: 2921)
            let value = arena.appendExpr(.symbolRef(sourceSymbol), type: sourceType)
            let callerID = arena.appendDecl(.function(KIRFunction(
                symbol: SymbolID(rawValue: 2922), name: interner.intern("caller"),
                params: [KIRParameter(symbol: sourceSymbol, type: sourceType)],
                returnType: primitiveType, body: [.returnValue(value)],
                isSuspend: false, isInline: false
            )))
            let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)
            try runLowering(module: module, interner: interner, moduleName: "ABIReturn",
                            sema: makeSemaModule(symbols: symbols, types: types).ctx)
            let lowered = try findKIRFunction(named: "caller", in: module, interner: interner)
            guard case let .returnValue(returned) = try #require(lowered.body.last) else {
                Issue.record("Expected primitive return")
                continue
            }
            if sourceType == primitiveType {
                #expect(returned == value, "Raw floating bits must not be unboxed again")
                #expect(lowered.body.count == 1)
            } else {
                #expect(returned != value)
                #expect(arena.exprType(returned) == primitiveType)
                let unbox = try #require(lowered.body.first { instruction in
                    if case let .call(_, _, args, result, _, _, _, _) = instruction {
                        return args == [value] && result == returned
                    }
                    return false
                })
                guard case let .call(_, callee, _, _, canThrow, thrownResult, _, _) = unbox else { continue }
                let expected = try loweringBoxingABI(.unbox, for: primitive, nonNull: true, staticPrimitive: true)
                #expect(callee == interner.intern(expected.name))
                #expect(!canThrow && thrownResult == nil)
            }
        }
    }
}
#endif
