@testable import CompilerCore
import Testing

extension TypeSystemTests {
    @Test
    func lubUsesNullableTypeParameterUpperBoundForNonNullInputs() {
        let types = TypeSystem()
        let symbols = SymbolTable()
        types.symbolTable = symbols

        let numberSymbol = SymbolID(rawValue: 100)
        let parameterSymbol = SymbolID(rawValue: 101)
        types.numberClassSymbol = numberSymbol

        let nullableNumber = types.make(.classType(ClassType(
            classSymbol: numberSymbol,
            nullability: .nullable
        )))
        symbols.setTypeParameterUpperBounds([nullableNumber], for: parameterSymbol)

        let nullableParameter = types.make(.typeParam(TypeParamType(
            symbol: parameterSymbol,
            nullability: .nullable
        )))
        let result = types.lub([types.makeNonNullable(nullableParameter), types.intType])
        let expected = types.make(.classType(ClassType(classSymbol: numberSymbol)))

        #expect(result == expected)
        #expect(!types.isSubtype(types.makeNonNullable(nullableParameter), expected))
    }

    @Test
    func lubExpandsTypeParameterUpperBoundsThroughCycles() {
        let types = TypeSystem()
        let symbols = SymbolTable()
        types.symbolTable = symbols

        let numberSymbol = SymbolID(rawValue: 200)
        let firstParameter = SymbolID(rawValue: 201)
        let secondParameter = SymbolID(rawValue: 202)
        types.numberClassSymbol = numberSymbol

        let firstType = types.make(.typeParam(TypeParamType(symbol: firstParameter)))
        let secondType = types.make(.typeParam(TypeParamType(symbol: secondParameter)))
        let nullableNumber = types.make(.classType(ClassType(
            classSymbol: numberSymbol,
            nullability: .nullable
        )))
        symbols.setTypeParameterUpperBounds([secondType], for: firstParameter)
        symbols.setTypeParameterUpperBounds([firstType, nullableNumber], for: secondParameter)

        let result = types.lub([firstType, types.intType])
        let expected = types.make(.classType(ClassType(classSymbol: numberSymbol)))

        #expect(result == expected)
    }
}
