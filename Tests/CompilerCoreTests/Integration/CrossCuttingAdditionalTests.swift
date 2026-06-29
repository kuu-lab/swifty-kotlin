#if canImport(Testing)
@testable import CompilerCore
import Testing

// MARK: - SymbolTable Missing Accessor Tests

@Suite struct SymbolTableAdditionalTests {
    @Test func testLookupByShortNameReturnsMatchingSymbols() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let name = interner.intern("foo")
        let id1 = symbols.define(
            kind: .function,
            name: name,
            fqName: [interner.intern("pkg"), name],
            declSite: nil,
            visibility: .public
        )
        let id2 = symbols.define(
            kind: .function,
            name: name,
            fqName: [interner.intern("other"), name],
            declSite: nil,
            visibility: .public
        )
        let results = symbols.lookupByShortName(name)
        #expect(results.contains(id1))
        #expect(results.contains(id2))
        #expect(results.count == 2)
    }

    @Test func testLookupByShortNameReturnsEmptyForUnknown() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        #expect(symbols.lookupByShortName(interner.intern("missing")) == [])
    }

    @Test func testSetAndGetSupertypeTypeArgs() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let parent = symbols.define(
            kind: .class,
            name: interner.intern("Parent"),
            fqName: [interner.intern("Parent")],
            declSite: nil,
            visibility: .public
        )
        let child = symbols.define(
            kind: .class,
            name: interner.intern("Child"),
            fqName: [interner.intern("Child")],
            declSite: nil,
            visibility: .public
        )
        let intType = types.make(.primitive(.int, .nonNull))
        let args: [TypeArg] = [.invariant(intType), .out(types.anyType)]
        symbols.setSupertypeTypeArgs(args, for: child, supertype: parent)
        let retrieved = symbols.supertypeTypeArgs(for: child, supertype: parent)
        #expect(retrieved == args)
    }

    @Test func testSupertypeTypeArgsReturnsEmptyForUnset() {
        let symbols = SymbolTable()
        let result = symbols.supertypeTypeArgs(
            for: SymbolID(rawValue: 0),
            supertype: SymbolID(rawValue: 1)
        )
        #expect(result == [])
    }

    @Test func testSetAndGetBackingFieldSymbol() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let prop = symbols.define(
            kind: .property,
            name: interner.intern("value"),
            fqName: [interner.intern("value")],
            declSite: nil,
            visibility: .public
        )
        let backingField = symbols.define(
            kind: .backingField,
            name: interner.intern("value$backing"),
            fqName: [interner.intern("value$backing")],
            declSite: nil,
            visibility: .private
        )
        symbols.setBackingFieldSymbol(backingField, for: prop)
        #expect(symbols.backingFieldSymbol(for: prop) == backingField)
    }

    @Test func testBackingFieldSymbolReturnsNilForUnset() {
        let symbols = SymbolTable()
        #expect(symbols.backingFieldSymbol(for: SymbolID(rawValue: 0)) == nil)
    }
}

// MARK: - BindingTable Read-Side Accessor Tests

@Suite struct BindingTableAdditionalTests {
    @Test func testExprTypeForMethod() {
        let bindings = BindingTable()
        let types = TypeSystem()
        let expr = ExprID(rawValue: 1)
        let intType = types.make(.primitive(.int, .nonNull))
        bindings.bindExprType(expr, type: intType)
        #expect(bindings.exprType(for: expr) == intType)
    }

    @Test func testExprTypeForReturnsNilWhenUnbound() {
        let bindings = BindingTable()
        #expect(bindings.exprType(for: ExprID(rawValue: 99)) == nil)
    }

    @Test func testIdentifierSymbolForMethod() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 1)
        let sym = SymbolID(rawValue: 1)
        bindings.bindIdentifier(expr, symbol: sym)
        #expect(bindings.identifierSymbol(for: expr) == sym)
    }

    @Test func testIdentifierSymbolForReturnsNilWhenUnbound() {
        let bindings = BindingTable()
        #expect(bindings.identifierSymbol(for: ExprID(rawValue: 99)) == nil)
    }

    @Test func testCallBindingForMethod() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 1)
        let binding = CallBinding(
            chosenCallee: SymbolID(rawValue: 1),
            substitutedTypeArguments: [],
            parameterMapping: [0: 1, 1: 0]
        )
        bindings.bindCall(expr, binding: binding)
        let retrieved = bindings.callBinding(for: expr)
        #expect(retrieved != nil)
        #expect(retrieved?.chosenCallee == SymbolID(rawValue: 1))
        #expect(retrieved?.parameterMapping == [0: 1, 1: 0])
    }

    @Test func testCallBindingForReturnsNilWhenUnbound() {
        let bindings = BindingTable()
        #expect(bindings.callBinding(for: ExprID(rawValue: 99)) == nil)
    }

    @Test func testDeclSymbolForMethod() {
        let bindings = BindingTable()
        let decl = DeclID(rawValue: 1)
        let sym = SymbolID(rawValue: 1)
        bindings.bindDecl(decl, symbol: sym)
        #expect(bindings.declSymbol(for: decl) == sym)
    }

    @Test func testDeclSymbolForReturnsNilWhenUnbound() {
        let bindings = BindingTable()
        #expect(bindings.declSymbol(for: DeclID(rawValue: 99)) == nil)
    }

    @Test func testIsSuperCallExprMarkAndCheck() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 1)
        #expect(!(bindings.isSuperCallExpr(expr)))
        bindings.markSuperCall(expr)
        #expect(bindings.isSuperCallExpr(expr))
    }

    @Test func testIsSuperCallExprReturnsFalseForUnmarked() {
        let bindings = BindingTable()
        #expect(!(bindings.isSuperCallExpr(ExprID(rawValue: 999))))
    }
}

// MARK: - TypeSystem Nominal Supertype TypeArgs Tests

@Suite struct TypeSystemAdditionalTests {
    @Test func testSetAndGetNominalSupertypeTypeArgs() {
        let ts = TypeSystem()
        let child = SymbolID(rawValue: 0)
        let parent = SymbolID(rawValue: 1)
        let intType = ts.make(.primitive(.int, .nonNull))
        let args: [TypeArg] = [.invariant(intType), .out(ts.anyType)]
        ts.setNominalSupertypeTypeArgs(args, for: child, supertype: parent)
        let retrieved = ts.nominalSupertypeTypeArgs(for: child, supertype: parent)
        #expect(retrieved == args)
    }

    @Test func testNominalSupertypeTypeArgsReturnsEmptyForUnset() {
        let ts = TypeSystem()
        let result = ts.nominalSupertypeTypeArgs(
            for: SymbolID(rawValue: 0),
            supertype: SymbolID(rawValue: 1)
        )
        #expect(result == [])
    }
}

// MARK: - ASTArena Edge Case Tests

@Suite struct ASTArenaAdditionalTests {
    @Test func testDeclReturnsNilForInvalidID() {
        let arena = ASTArena()
        // DeclID uses Int32, so -1 is the canonical .invalid sentinel
        #expect(arena.decl(DeclID.invalid) == nil)
    }

    @Test func testDeclReturnsNilForOutOfRangeID() {
        let arena = ASTArena()
        #expect(arena.decl(DeclID(rawValue: 999)) == nil)
    }

    @Test func testTypeRefReturnsNilForInvalidID() {
        let arena = ASTArena()
        #expect(arena.typeRef(TypeRefID(rawValue: -1)) == nil)
    }

    @Test func testTypeRefReturnsNilForOutOfRangeID() {
        let arena = ASTArena()
        #expect(arena.typeRef(TypeRefID(rawValue: 999)) == nil)
    }
}

// MARK: - DataFlowAnalyzer Struct Init Edge Cases

@Suite struct DataFlowStructTests {
    @Test func testDataFlowStateDefaultInit() {
        let state = DataFlowState()
        #expect(state.variables.isEmpty)
    }

    @Test func testVariableFlowStateEquality() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let a = VariableFlowState(
            possibleTypes: [intType],
            nullability: .nonNull,
            isStable: true
        )
        let b = VariableFlowState(
            possibleTypes: [intType],
            nullability: .nonNull,
            isStable: true
        )
        let c = VariableFlowState(
            possibleTypes: [intType],
            nullability: .nullable,
            isStable: true
        )
        #expect(a == b)
        #expect(a != c)
    }

    @Test func testWhenBranchSummaryAutoDerivation() {
        // When hasTrueCase/hasFalseCase are not explicitly provided,
        // they should be derived from coveredSymbols containing
        // InternedString(rawValue: 1) and InternedString(rawValue: 2).
        // WARNING: These sentinel values are coupled to DataFlowAnalysis.swift:38-39.
        // If the implementation changes these magic constants, this test must be
        // updated in sync.
        let trueSymbol = InternedString(rawValue: 1)
        let falseSymbol = InternedString(rawValue: 2)

        let summaryBoth = WhenBranchSummary(
            coveredSymbols: [trueSymbol, falseSymbol],
            hasElse: false
        )
        #expect(summaryBoth.hasTrueCase)
        #expect(summaryBoth.hasFalseCase)

        let summaryTrueOnly = WhenBranchSummary(
            coveredSymbols: [trueSymbol],
            hasElse: false
        )
        #expect(summaryTrueOnly.hasTrueCase)
        #expect(!(summaryTrueOnly.hasFalseCase))

        let summaryNone = WhenBranchSummary(
            coveredSymbols: [],
            hasElse: false
        )
        #expect(!(summaryNone.hasTrueCase))
        #expect(!(summaryNone.hasFalseCase))

        // Explicit override should take precedence
        let summaryExplicit = WhenBranchSummary(
            coveredSymbols: [],
            hasElse: false,
            hasTrueCase: true,
            hasFalseCase: true
        )
        #expect(summaryExplicit.hasTrueCase)
        #expect(summaryExplicit.hasFalseCase)
    }
}

// MARK: - DiagnosticEngine.hasError Tests

@Suite struct DiagnosticEngineAdditionalTests {
    @Test func testHasErrorReturnsFalseWhenEmpty() {
        let engine = DiagnosticEngine()
        #expect(!(engine.hasError))
    }

    @Test func testHasErrorReturnsFalseWithOnlyWarnings() {
        let engine = DiagnosticEngine()
        engine.warning("W001", "some warning", range: nil)
        engine.note("N001", "some note", range: nil)
        engine.info("I001", "some info", range: nil)
        #expect(!(engine.hasError))
    }

    @Test func testHasErrorReturnsTrueWithError() {
        let engine = DiagnosticEngine()
        engine.warning("W001", "some warning", range: nil)
        engine.error("E001", "some error", range: nil)
        #expect(engine.hasError)
    }
}

// MARK: - CallableValueCallBinding and CatchClauseBinding Init Tests

@Suite struct BindingModelAdditionalTests {
    @Test func testCallableValueCallBindingInit() {
        let types = TypeSystem()
        let fnType = types.make(.functionType(FunctionType(
            params: [types.make(.primitive(.int, .nonNull))],
            returnType: types.unitType
        )))
        let binding = CallableValueCallBinding(
            target: .symbol(SymbolID(rawValue: 1)),
            functionType: fnType,
            parameterMapping: [0: 0]
        )
        #expect(binding.target == .symbol(SymbolID(rawValue: 1)))
        #expect(binding.functionType == fnType)
        #expect(binding.parameterMapping == [0: 0])
    }

    @Test func testCallableValueCallBindingNilTarget() {
        let types = TypeSystem()
        let fnType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.unitType
        )))
        let binding = CallableValueCallBinding(
            target: nil,
            functionType: fnType,
            parameterMapping: [:]
        )
        #expect(binding.target == nil)
        #expect(binding.functionType == fnType)
    }

    @Test func testCatchClauseBindingDefaultParameterSymbol() {
        let types = TypeSystem()
        let binding = CatchClauseBinding(parameterType: types.anyType)
        #expect(binding.parameterSymbol == .invalid)
        #expect(binding.parameterType == types.anyType)
    }

    @Test func testCatchClauseBindingWithExplicitSymbol() {
        let types = TypeSystem()
        let sym = SymbolID(rawValue: 1)
        let binding = CatchClauseBinding(parameterSymbol: sym, parameterType: types.anyType)
        #expect(binding.parameterSymbol == sym)
    }

    @Test func testCallableTargetEquality() {
        let sym1 = SymbolID(rawValue: 1)
        let sym2 = SymbolID(rawValue: 2)
        #expect(CallableTarget.symbol(sym1) == CallableTarget.symbol(sym1))
        #expect(CallableTarget.symbol(sym1) != CallableTarget.symbol(sym2))
        #expect(CallableTarget.localValue(sym1) == CallableTarget.localValue(sym1))
        #expect(CallableTarget.symbol(sym1) != CallableTarget.localValue(sym1))
    }
}
#endif
