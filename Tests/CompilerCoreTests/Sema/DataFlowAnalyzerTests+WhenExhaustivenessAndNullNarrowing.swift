#if canImport(Testing)
@testable import CompilerCore
import Testing

extension DataFlowAnalyzerTests {
    @Test func testIsWhenExhaustiveNonSealedClassReturnsFalse() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let className = interner.intern("Foo")
        let classSym = symbols.define(kind: .class, name: className, fqName: [className], declSite: nil, visibility: .public)
        let classType = types.make(.classType(ClassType(classSymbol: classSym)))

        let summary = WhenBranchSummary(coveredSymbols: [className], hasElse: false)
        #expect(!analyzer.isWhenExhaustive(subjectType: classType, branches: summary, sema: sema))
    }

    @Test func testIsWhenExhaustiveEmptyEnumReturnsFalse() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let enumName = interner.intern("Empty")
        let enumSym = symbols.define(kind: .enumClass, name: enumName, fqName: [enumName], declSite: nil, visibility: .public)
        let enumType = types.make(.classType(ClassType(classSymbol: enumSym)))

        let summary = WhenBranchSummary(coveredSymbols: [], hasElse: false)
        #expect(!analyzer.isWhenExhaustive(subjectType: enumType, branches: summary, sema: sema))
    }

    @Test func testIsWhenExhaustiveEmptySealedReturnsFalse() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let sealedName = interner.intern("Empty")
        let sealedSym = symbols.define(
            kind: .class, name: sealedName, fqName: [sealedName],
            declSite: nil, visibility: .public, flags: .sealedType
        )
        let sealedType = types.make(.classType(ClassType(classSymbol: sealedSym)))

        let summary = WhenBranchSummary(coveredSymbols: [], hasElse: false)
        #expect(!analyzer.isWhenExhaustive(subjectType: sealedType, branches: summary, sema: sema))
    }

    // MARK: - resolvedTypeFromFlowState

    @Test func testResolvedTypeFromFlowStateReturnsSingleType() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let sym = SymbolID(rawValue: 0)
        let state = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true),
        ])
        #expect(analyzer.resolvedTypeFromFlowState(state, symbol: sym) == intType)
    }

    @Test func testResolvedTypeFromFlowStateReturnsNilForMultipleTypes() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let sym = SymbolID(rawValue: 0)
        let state = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType, stringType], nullability: .nonNull, isStable: true),
        ])
        #expect(analyzer.resolvedTypeFromFlowState(state, symbol: sym) == nil)
    }

    @Test func testResolvedTypeFromFlowStateReturnsNilForUnknownSymbol() {
        let analyzer = DataFlowAnalyzer()
        let state = DataFlowState()
        #expect(analyzer.resolvedTypeFromFlowState(state, symbol: SymbolID(rawValue: 0)) == nil)
    }

    @Test func testResolvedTypeFromFlowStateReturnsNilForEmptyTypes() {
        let analyzer = DataFlowAnalyzer()
        let sym = SymbolID(rawValue: 0)
        let state = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [], nullability: .nonNull, isStable: true),
        ])
        #expect(analyzer.resolvedTypeFromFlowState(state, symbol: sym) == nil)
    }

    // MARK: - whenElseState

    @Test func testWhenElseStateWithNoExplicitNullBranchReturnsBase() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let nullableInt = types.make(.primitive(.int, .nullable))
        let base = DataFlowState()

        let result = analyzer.whenElseState(
            subjectSymbol: sym,
            subjectType: nullableInt,
            hasExplicitNullBranch: false,
            base: base,
            sema: sema
        )
        #expect(result == base)
    }

    @Test func testWhenElseStateWithExplicitNullBranchNarrowsToNonNull() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let nullableInt = types.make(.primitive(.int, .nullable))
        let nonNullInt = types.make(.primitive(.int, .nonNull))
        let base = DataFlowState()

        let result = analyzer.whenElseState(
            subjectSymbol: sym,
            subjectType: nullableInt,
            hasExplicitNullBranch: true,
            base: base,
            sema: sema
        )
        #expect(result.variables[sym]?.possibleTypes == [nonNullInt])
        #expect(result.variables[sym]?.nullability == .nonNull)
    }

    // MARK: - whenNonNullBranchState

    @Test func testWhenNonNullBranchStateNarrowsToNonNull() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let nullableString = types.make(.primitive(.string, .nullable))
        let nonNullString = types.make(.primitive(.string, .nonNull))
        let base = DataFlowState()

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: nullableString,
            base: base,
            sema: sema
        )
        #expect(result.variables[sym]?.possibleTypes == [nonNullString])
        #expect(result.variables[sym]?.nullability == .nonNull)
    }

    @Test func testWhenNonNullBranchStateAlreadyNonNull() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let nonNullInt = types.make(.primitive(.int, .nonNull))
        let base = DataFlowState()

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: nonNullInt,
            base: base,
            sema: sema
        )
        #expect(result.variables[sym]?.possibleTypes == [nonNullInt])
    }

    // MARK: - makeTypeNonNullable coverage through whenNonNullBranchState

    @Test func testMakeTypeNonNullableForNullableAny() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: types.nullableAnyType,
            base: base,
            sema: sema
        )
        #expect(result.variables[sym]?.possibleTypes == [types.anyType])
    }

    @Test func testMakeTypeNonNullableForNullableClass() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()
        let classSym = SymbolID(rawValue: 10)
        let nullableClass = types.make(.classType(ClassType(classSymbol: classSym, nullability: .nullable)))
        let nonNullClass = types.make(.classType(ClassType(classSymbol: classSym, nullability: .nonNull)))

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: nullableClass,
            base: base,
            sema: sema
        )
        #expect(result.variables[sym]?.possibleTypes == [nonNullClass])
    }

    @Test func testMakeTypeNonNullableForNullableTypeParam() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()
        let tpSym = SymbolID(rawValue: 10)
        let nullableTP = types.make(.typeParam(TypeParamType(symbol: tpSym, nullability: .nullable)))
        let nonNullTP = types.make(.typeParam(TypeParamType(symbol: tpSym, nullability: .nonNull)))

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: nullableTP,
            base: base,
            sema: sema
        )
        #expect(result.variables[sym]?.possibleTypes == [nonNullTP])
    }

    @Test func testMakeTypeNonNullableForNullableFunctionType() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()
        let intType = types.make(.primitive(.int, .nonNull))
        let nullableFn = types.make(.functionType(FunctionType(params: [], returnType: intType, nullability: .nullable)))
        let nonNullFn = types.make(.functionType(FunctionType(params: [], returnType: intType, nullability: .nonNull)))

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: nullableFn,
            base: base,
            sema: sema
        )
        #expect(result.variables[sym]?.possibleTypes == [nonNullFn])
    }

    @Test func testMakeTypeNonNullableForNonNullableTypeIsIdentity() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()
        let intType = types.make(.primitive(.int, .nonNull))

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: intType,
            base: base,
            sema: sema
        )
        #expect(result.variables[sym]?.possibleTypes == [intType])
    }

}
#endif
