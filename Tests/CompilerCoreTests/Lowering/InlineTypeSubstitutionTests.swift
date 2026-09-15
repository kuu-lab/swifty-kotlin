#if canImport(Testing)
@testable import CompilerCore
import Testing

struct InlineTypeSubstitutionTests {
    @Test
    func testBuildCollectsNestedGenericNullableFunctionReceiverAndReturnTypes() throws {
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )
        let inlineSymbol = SymbolID(rawValue: 1)
        let parameterSymbol = SymbolID(rawValue: 2)
        let typeParameterT = SymbolID(rawValue: 3)
        let typeParameterU = SymbolID(rawValue: 4)
        let typeParameterV = SymbolID(rawValue: 5)
        let listSymbol = SymbolID(rawValue: 6)

        let nullableT = types.make(.typeParam(TypeParamType(symbol: typeParameterT, nullability: .nullable)))
        let u = types.make(.typeParam(TypeParamType(symbol: typeParameterU)))
        let v = types.make(.typeParam(TypeParamType(symbol: typeParameterV)))
        let expectedList = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.invariant(u)],
            nullability: .nullable
        )))
        let expectedFunction = types.make(.functionType(FunctionType(
            receiver: nullableT,
            params: [expectedList],
            returnType: v,
            nullability: .nullable
        )))

        let nullableString = types.make(.stringStruct(.nullable))
        let intType = types.make(.primitive(.int, .nonNull))
        let nullableListOfInt = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.invariant(intType)],
            nullability: .nullable
        )))
        let longType = types.make(.primitive(.long, .nonNull))
        let actualFunction = types.make(.functionType(FunctionType(
            receiver: nullableString,
            params: [nullableListOfInt],
            returnType: longType,
            nullability: .nullable
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [expectedFunction],
                returnType: v,
                valueParameterSymbols: [parameterSymbol],
                typeParameterSymbols: [typeParameterT, typeParameterU, typeParameterV]
            ),
            for: inlineSymbol
        )

        let arena = KIRArena()
        let argument = arena.appendTemporary(type: actualFunction)
        let inlineTarget = KIRFunction(
            symbol: inlineSymbol,
            name: InternedString(rawValue: 0),
            params: [KIRParameter(symbol: parameterSymbol, type: expectedFunction)],
            returnType: v,
            body: [],
            isSuspend: false,
            isInline: true
        )
        let module = KIRModule(files: [], arena: arena)

        let substitution = try #require(
            InlineTypeSubstitution.buildInlineTypeSubstitution(
                inlineTarget: inlineTarget,
                arguments: [argument],
                module: module,
                sema: sema
            )
        )
        let tVariable = try #require(substitution.typeVarBySymbol[typeParameterT])
        let uVariable = try #require(substitution.typeVarBySymbol[typeParameterU])
        #expect(substitution.substitution[tVariable] == nullableString)
        #expect(substitution.substitution[uVariable] == intType)

        let vVariable = try #require(substitution.typeVarBySymbol[typeParameterV])
        #expect(substitution.substitution[vVariable] == longType)

        let substituted = try #require(
            InlineTypeSubstitution.substituteInlineType(
                expectedFunction,
                using: substitution,
                sema: sema
            )
        )
        guard case let .functionType(result) = types.kind(of: substituted) else {
            Issue.record("Expected a substituted function type")
            return
        }
        #expect(result.nullability == .nullable)
        #expect(result.receiver == nullableString)
        #expect(result.params == [nullableListOfInt])
        #expect(result.returnType == longType)
    }

    @Test
    func testBuildTypeParamTokenValuesMapsReifiedTypeParametersToHiddenArguments() throws {
        let symbols = SymbolTable()
        let types = TypeSystem()
        let typeParameterT = SymbolID(rawValue: 1)
        let typeParameterU = SymbolID(rawValue: 2)
        let inlineSymbol = SymbolID(rawValue: 3)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: types.unitType,
                typeParameterSymbols: [typeParameterT, typeParameterU],
                reifiedTypeParameterIndices: [1]
            ),
            for: inlineSymbol
        )
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )
        let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParameterU)
        let tokenValue = KIRExprID(rawValue: 42)
        let inlineTarget = KIRFunction(
            symbol: inlineSymbol,
            name: InternedString(rawValue: 0),
            params: [KIRParameter(symbol: tokenSymbol, type: types.anyType)],
            returnType: types.unitType,
            body: [],
            isSuspend: false,
            isInline: true
        )

        let values = InlineTypeSubstitution.buildTypeParamTokenValues(
            inlineTarget: inlineTarget,
            parameterValues: [tokenSymbol: tokenValue],
            sema: sema
        )

        #expect(values == [typeParameterU: tokenValue])
        #expect(values[typeParameterT] == nil)
    }
}
#endif
