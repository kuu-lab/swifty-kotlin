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
        // `t ?: 1` joins `T & Any` (Kotlin's definitely-non-null view of the
        // lhs) with `Int` — the bound's non-null projection `Number`.
        let definitelyNonNullParameter = types.definitelyNonNullForm(of: nullableParameter)
        let result = types.lub([definitelyNonNullParameter, types.intType])
        let expected = types.make(.classType(ClassType(classSymbol: numberSymbol)))

        #expect(result == expected)
        #expect(!types.isSubtype(definitelyNonNullParameter, expected))
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

        let result = types.lub([types.definitelyNonNullForm(of: firstType), types.intType])
        let expected = types.make(.classType(ClassType(classSymbol: numberSymbol)))

        #expect(result == expected)
    }

    @Test
    func lubJoinsUnrelatedTypeParametersAtNullableAny() {
        let types = TypeSystem()
        let symbols = SymbolTable()
        types.symbolTable = symbols

        // Unbounded Kotlin type parameters have an implicit `Any?` upper
        // bound, so `arrayOf(k, v)` joins at `Any?` — not `Any` (KUU-2693).
        let firstType = types.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 300))))
        let secondType = types.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 301))))

        #expect(types.lub([firstType, secondType]) == types.nullableAnyType)
        #expect(types.lub([firstType, types.intType]) == types.nullableAnyType)
    }

    @Test
    func lubPreservesTypeParameterWhenJoinedWithDefinitelyNonNullForm() {
        let types = TypeSystem()
        let parameter = types.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 700))))
        let definitelyNonNull = types.definitelyNonNullForm(of: parameter)

        #expect(types.lub([definitelyNonNull, parameter]) == parameter)
        #expect(types.lub([parameter, definitelyNonNull]) == parameter)
    }

    @Test
    func lubKeepsNullableBoundOfTypeParameter() {
        let types = TypeSystem()
        let symbols = SymbolTable()
        types.symbolTable = symbols

        let numberSymbol = SymbolID(rawValue: 400)
        let parameterSymbol = SymbolID(rawValue: 401)
        types.numberClassSymbol = numberSymbol

        let nullableNumber = types.make(.classType(ClassType(
            classSymbol: numberSymbol,
            nullability: .nullable
        )))
        symbols.setTypeParameterUpperBounds([nullableNumber], for: parameterSymbol)

        // `arrayOf(t, 1)` for `T : Number?` joins at `Number?` — the
        // parameter can hold `null` through its bound (KUU-2693).
        let parameter = types.make(.typeParam(TypeParamType(symbol: parameterSymbol)))
        let expected = types.make(.classType(ClassType(
            classSymbol: numberSymbol,
            nullability: .nullable
        )))
        #expect(types.lub([parameter, types.intType]) == expected)
    }

    @Test
    func nullableViewOfDefinitelyNonNullParameterDropsAnyConjunct() {
        let types = TypeSystem()
        let symbols = SymbolTable()
        types.symbolTable = symbols

        let parameter = types.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 500))))
        let nonNull = types.definitelyNonNullForm(of: parameter)

        // `T & Any` is definitely non-null; its nullable view is `T?` —
        // `if (t != null) t else null` joins at `T?`, not `Any?` (KUU-2693).
        #expect(types.isDefinitelyNonNull(nonNull))
        #expect(types.makeNullable(nonNull) == types.makeNullable(parameter))
    }

    @Test
    func nullNarrowedIntersectionStaysAssignableToBothBounds() {
        let types = TypeSystem()
        let symbols = SymbolTable()
        types.symbolTable = symbols

        let parameter = types.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 600))))
        // `k == null` narrows `k` to `Nothing? & K`: assignable to `Nothing?`
        // and to `K`, but the type itself is nullable (KUU-2693).
        let narrowed = types.make(.intersection([types.nullableNothingType, parameter]))

        #expect(types.nullability(of: narrowed) == .nullable)
        #expect(!types.isDefinitelyNonNull(narrowed))
        #expect(types.isSubtype(narrowed, types.nullableNothingType))
        #expect(types.isSubtype(narrowed, parameter))
        #expect(types.lub([narrowed, types.make(.typeParam(TypeParamType(
            symbol: SymbolID(rawValue: 601)
        )))]) == types.nullableAnyType)
    }
}
