#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension DataFlowAnalyzerTests {
    @Test func testCapturedSealedUpperBoundIsUsedForWhenExhaustiveness() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let sealedName = interner.intern("Root")
        let sealedSymbol = symbols.define(
            kind: .class, name: sealedName, fqName: [sealedName],
            declSite: nil, visibility: .public, flags: .sealedType
        )
        let firstName = interner.intern("First")
        let secondName = interner.intern("Second")
        let firstSymbol = symbols.define(kind: .class, name: firstName, fqName: [firstName], declSite: nil, visibility: .public)
        let secondSymbol = symbols.define(kind: .class, name: secondName, fqName: [secondName], declSite: nil, visibility: .public)
        symbols.setDirectSupertypes([sealedSymbol], for: firstSymbol)
        symbols.setDirectSupertypes([sealedSymbol], for: secondSymbol)

        let sealedType = types.make(.classType(ClassType(classSymbol: sealedSymbol)))
        let typeParameter = symbols.define(
            kind: .typeParameter, name: interner.intern("T"), fqName: [interner.intern("T")],
            declSite: nil, visibility: .private
        )
        let capturedType = types.makeCapturedType(
            parameter: typeParameter,
            lower: types.nothingType,
            upper: sealedType
        )
        let complete = WhenBranchSummary(coveredSymbols: [firstName, secondName], hasElse: false)
        let incomplete = WhenBranchSummary(coveredSymbols: [firstName], hasElse: false)

        #expect(analyzer.isWhenExhaustive(subjectType: capturedType, branches: complete, sema: sema))
        #expect(!analyzer.isWhenExhaustive(subjectType: capturedType, branches: incomplete, sema: sema))
        #expect(analyzer.subjectRequiresStatementExhaustiveness(subjectType: capturedType, sema: sema))
        #expect(analyzer.missingSealedBranches(subjectType: capturedType, branches: incomplete, sema: sema) == [secondName])
    }

    @Test func testCapturedIntersectionUpperBoundUsesItsSealedComponent() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let sealedName = interner.intern("Root")
        let sealedSymbol = symbols.define(
            kind: .class, name: sealedName, fqName: [sealedName],
            declSite: nil, visibility: .public, flags: .sealedType
        )
        let markerName = interner.intern("Marker")
        let markerSymbol = symbols.define(
            kind: .interface, name: markerName, fqName: [markerName],
            declSite: nil, visibility: .public
        )
        let childName = interner.intern("Child")
        let childSymbol = symbols.define(kind: .class, name: childName, fqName: [childName], declSite: nil, visibility: .public)
        symbols.setDirectSupertypes([sealedSymbol, markerSymbol], for: childSymbol)

        let sealedType = types.make(.classType(ClassType(classSymbol: sealedSymbol)))
        let markerType = types.make(.classType(ClassType(classSymbol: markerSymbol)))
        let intersection = types.make(.intersection([sealedType, markerType]))
        let typeParameterName = interner.intern("T")
        let typeParameter = symbols.define(
            kind: .typeParameter, name: typeParameterName, fqName: [typeParameterName],
            declSite: nil, visibility: .private
        )
        let capturedType = types.makeCapturedType(
            parameter: typeParameter,
            lower: types.nothingType,
            upper: intersection
        )
        let complete = WhenBranchSummary(coveredSymbols: [childName], hasElse: false)

        #expect(analyzer.isWhenExhaustive(subjectType: capturedType, branches: complete, sema: sema))
    }

    @Test func testNullableCapturedSealedUpperBoundRequiresNullBranch() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let sealedName = interner.intern("Root")
        let sealedSymbol = symbols.define(
            kind: .class, name: sealedName, fqName: [sealedName],
            declSite: nil, visibility: .public, flags: .sealedType
        )
        let childName = interner.intern("Child")
        let childSymbol = symbols.define(kind: .class, name: childName, fqName: [childName], declSite: nil, visibility: .public)
        symbols.setDirectSupertypes([sealedSymbol], for: childSymbol)

        let nullableSealedType = types.make(.classType(ClassType(classSymbol: sealedSymbol, nullability: .nullable)))
        let typeParameterName = interner.intern("T")
        let typeParameter = symbols.define(
            kind: .typeParameter, name: typeParameterName, fqName: [typeParameterName],
            declSite: nil, visibility: .private
        )
        let capturedType = types.makeCapturedType(
            parameter: typeParameter,
            lower: types.nullableNothingType,
            upper: nullableSealedType
        )
        let withoutNull = WhenBranchSummary(coveredSymbols: [childName], hasElse: false)
        let withNull = WhenBranchSummary(coveredSymbols: [childName], hasElse: false, hasNullCase: true)

        #expect(!analyzer.isWhenExhaustive(subjectType: capturedType, branches: withoutNull, sema: sema))
        #expect(analyzer.isWhenExhaustive(subjectType: capturedType, branches: withNull, sema: sema))
    }

    @Test(arguments: [false, true])
    func testSealedInterfaceCoverageUsesResolvedSymbols(useMetadata: Bool) {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()
        func define(_ name: String, kind: SymbolKind = .class, flags: SymbolFlags = []) -> SymbolID {
            let interned = interner.intern(name)
            return symbols.define(kind: kind, name: interned, fqName: [interned], declSite: nil, visibility: .public, flags: flags)
        }
        let root = define("Root", flags: .sealedType)
        let tag = define("Tag", kind: .interface)
        let childTag = define("ChildTag", kind: .interface)
        let taggedBase = define("TaggedBase")
        let leaf = define("Leaf")
        let other = define("Other")
        symbols.setDirectSupertypes([tag], for: childTag)
        symbols.setDirectSupertypes([childTag], for: taggedBase)
        symbols.setDirectSupertypes([root, taggedBase], for: leaf)
        symbols.setDirectSupertypes([root], for: other)
        if useMetadata {
            symbols.setSealedSubclasses([leaf, other], for: root)
        }
        let rootType = types.make(.classType(ClassType(classSymbol: root)))
        let incomplete = WhenBranchSummary(coveredSymbols: [], hasElse: false, coveredTypeSymbols: [tag])
        #expect(!analyzer.isWhenExhaustive(subjectType: rootType, branches: incomplete, sema: sema))
        #expect(analyzer.missingSealedBranches(subjectType: rootType, branches: incomplete, sema: sema) == [interner.intern("Other")])

        let complete = WhenBranchSummary(coveredSymbols: [], hasElse: false, coveredTypeSymbols: [tag, other])
        #expect(analyzer.isWhenExhaustive(subjectType: rootType, branches: complete, sema: sema))
        #expect(analyzer.missingSealedBranches(subjectType: rootType, branches: complete, sema: sema) == nil)

        if useMetadata {
            symbols.setSealedSubclasses([], for: root)
            #expect(!analyzer.isWhenExhaustive(subjectType: rootType, branches: complete, sema: sema))
        }
    }

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

    // KUU-3775: covering every grandchild of a nested sealed child counts as
    // covering that child (`is A` + `is B` exhaust `N : F` inside `when (f: F)`).
    @Test(arguments: [false, true])
    func testNestedSealedSubtypeCoveredByGrandchildren(useMetadata: Bool) {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()
        func define(_ name: String, kind: SymbolKind = .class, flags: SymbolFlags = []) -> SymbolID {
            let interned = interner.intern(name)
            return symbols.define(kind: kind, name: interned, fqName: [interned], declSite: nil, visibility: .public, flags: flags)
        }
        let f = define("F", kind: .interface, flags: .sealedType)
        let n = define("N", kind: .interface, flags: .sealedType)
        let a = define("A")
        let b = define("B")
        let c = define("C")
        symbols.setDirectSupertypes([f], for: n)
        symbols.setDirectSupertypes([n], for: a)
        symbols.setDirectSupertypes([n], for: b)
        symbols.setDirectSupertypes([f], for: c)
        if useMetadata {
            symbols.setSealedSubclasses([n, c], for: f)
            symbols.setSealedSubclasses([a, b], for: n)
        }
        let fType = types.make(.classType(ClassType(classSymbol: f)))

        // `is A` + `is B` + `is C` exhausts F through N's covered children.
        let complete = WhenBranchSummary(coveredSymbols: [], hasElse: false, coveredTypeSymbols: [a, b, c])
        #expect(analyzer.isWhenExhaustive(subjectType: fType, branches: complete, sema: sema))
        #expect(analyzer.missingSealedBranches(subjectType: fType, branches: complete, sema: sema) == nil)

        // Direct `is N` coverage still counts.
        let directN = WhenBranchSummary(coveredSymbols: [], hasElse: false, coveredTypeSymbols: [n, c])
        #expect(analyzer.isWhenExhaustive(subjectType: fType, branches: directN, sema: sema))

        // A partially covered sealed child reports the uncovered grandchild
        // (`is B`), not the intermediate `N` — matching kotlinc's message.
        let partial = WhenBranchSummary(coveredSymbols: [], hasElse: false, coveredTypeSymbols: [a, c])
        #expect(!analyzer.isWhenExhaustive(subjectType: fType, branches: partial, sema: sema))
        #expect(analyzer.missingSealedBranches(subjectType: fType, branches: partial, sema: sema) == [interner.intern("B")])

        // Nothing under N covered: the diagnostic enumerates its leaves.
        let noneUnderN = WhenBranchSummary(coveredSymbols: [], hasElse: false, coveredTypeSymbols: [c])
        #expect(!analyzer.isWhenExhaustive(subjectType: fType, branches: noneUnderN, sema: sema))
        #expect(
            Set(analyzer.missingSealedBranches(subjectType: fType, branches: noneUnderN, sema: sema) ?? [])
                == [interner.intern("A"), interner.intern("B")]
        )
    }

    // KUU-3775: exhaustiveness propagates through more than one sealed level.
    @Test func testDeeplyNestedSealedCoverage() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()
        func define(_ name: String, kind: SymbolKind = .class, flags: SymbolFlags = []) -> SymbolID {
            let interned = interner.intern(name)
            return symbols.define(kind: kind, name: interned, fqName: [interned], declSite: nil, visibility: .public, flags: flags)
        }
        let r = define("R", kind: .interface, flags: .sealedType)
        let mid = define("Mid", kind: .interface, flags: .sealedType)
        let leaf = define("Leaf", kind: .interface, flags: .sealedType)
        let x = define("X")
        let y = define("Y")
        let z = define("Z")
        let w = define("W")
        symbols.setDirectSupertypes([r], for: mid)
        symbols.setDirectSupertypes([mid], for: leaf)
        symbols.setDirectSupertypes([leaf], for: x)
        symbols.setDirectSupertypes([leaf], for: y)
        symbols.setDirectSupertypes([mid], for: z)
        symbols.setDirectSupertypes([r], for: w)
        let rType = types.make(.classType(ClassType(classSymbol: r)))

        let complete = WhenBranchSummary(coveredSymbols: [], hasElse: false, coveredTypeSymbols: [x, y, z, w])
        #expect(analyzer.isWhenExhaustive(subjectType: rType, branches: complete, sema: sema))

        let missingY = WhenBranchSummary(coveredSymbols: [], hasElse: false, coveredTypeSymbols: [x, z, w])
        #expect(!analyzer.isWhenExhaustive(subjectType: rType, branches: missingY, sema: sema))
        #expect(analyzer.missingSealedBranches(subjectType: rType, branches: missingY, sema: sema) == [interner.intern("Y")])
    }

    // KUU-3775: an enum subtype nested in a sealed hierarchy is exhausted by
    // enumerating all of its entries (`E.X` + `E.Y` cover `E : F`).
    @Test(arguments: [false, true])
    func testEnumSubtypeCoveredByEntries(useMetadata: Bool) {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()
        let fName = interner.intern("F")
        let eName = interner.intern("E")
        let cName = interner.intern("C")
        let f = symbols.define(kind: .interface, name: fName, fqName: [fName], declSite: nil, visibility: .public, flags: .sealedType)
        let e = symbols.define(kind: .enumClass, name: eName, fqName: [eName], declSite: nil, visibility: .public)
        let c = symbols.define(kind: .class, name: cName, fqName: [cName], declSite: nil, visibility: .public)
        let xName = interner.intern("X")
        let yName = interner.intern("Y")
        _ = symbols.define(kind: .field, name: xName, fqName: [eName, xName], declSite: nil, visibility: .public)
        _ = symbols.define(kind: .field, name: yName, fqName: [eName, yName], declSite: nil, visibility: .public)
        symbols.setDirectSupertypes([f], for: e)
        symbols.setDirectSupertypes([f], for: c)
        if useMetadata {
            symbols.setSealedSubclasses([e, c], for: f)
        }
        let fType = types.make(.classType(ClassType(classSymbol: f)))

        let complete = WhenBranchSummary(coveredSymbols: [xName, yName], hasElse: false, coveredTypeSymbols: [c])
        #expect(analyzer.isWhenExhaustive(subjectType: fType, branches: complete, sema: sema))
        #expect(analyzer.missingSealedBranches(subjectType: fType, branches: complete, sema: sema) == nil)

        // `is E` coverage still counts.
        let directE = WhenBranchSummary(coveredSymbols: [], hasElse: false, coveredTypeSymbols: [e, c])
        #expect(analyzer.isWhenExhaustive(subjectType: fType, branches: directE, sema: sema))

        // A missing entry is reported by its own name (`Y`), matching kotlinc.
        let missingY = WhenBranchSummary(coveredSymbols: [xName], hasElse: false, coveredTypeSymbols: [c])
        #expect(!analyzer.isWhenExhaustive(subjectType: fType, branches: missingY, sema: sema))
        #expect(analyzer.missingSealedBranches(subjectType: fType, branches: missingY, sema: sema) == [yName])
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
        let stringType = types.stringType
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
        let nullableString = types.makeNullable(types.stringType)
        let nonNullString = types.stringType
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
        // Bare `T` stays null-capable through its implicit `Any?` bound, so the
        // definitely-non-null refinement is `T & Any` (KUU-2693), not plain `T`.
        let definitelyNonNullTP = types.make(.intersection([nonNullTP, types.anyType]))
        #expect(result.variables[sym]?.possibleTypes == [definitelyNonNullTP])
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
