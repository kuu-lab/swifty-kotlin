@testable import CompilerCore
import Testing

extension SymbolTableTests {
    @Test
    func testParentSymbolReturnsNilForUnset() {
        let symbols = SymbolTable()
        #expect(symbols.parentSymbol(for: SymbolID(rawValue: 0)) == nil)
    }

    // MARK: - Type Parameter Upper Bound

    @Test
    func testSetAndGetTypeParameterUpperBound() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let id = symbols.define(
            kind: .typeParameter,
            name: interner.intern("T"),
            fqName: [interner.intern("T")],
            declSite: nil,
            visibility: .public
        )
        symbols.setTypeParameterUpperBounds([types.anyType], for: id)
        #expect(symbols.typeParameterUpperBound(for: id) == types.anyType)
    }

    @Test
    func testSetTypeParameterUpperBoundsDeduplicatesBounds() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let id = symbols.define(
            kind: .typeParameter,
            name: interner.intern("T"),
            fqName: [interner.intern("T")],
            declSite: nil,
            visibility: .public
        )

        symbols.setTypeParameterUpperBounds([types.anyType, types.nullableAnyType, types.anyType], for: id)

        #expect(symbols.typeParameterUpperBounds(for: id) == [types.anyType, types.nullableAnyType])
    }

    @Test
    func testTypeParameterUpperBoundReturnsNilForUnset() {
        let symbols = SymbolTable()
        #expect(symbols.typeParameterUpperBound(for: SymbolID(rawValue: 0)) == nil)
    }

    // MARK: - Source File ID

    @Test
    func testSetAndGetSourceFileID() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let id = symbols.define(kind: .class, name: interner.intern("C"), fqName: [interner.intern("C")], declSite: nil, visibility: .public)
        let fileID = FileID(rawValue: 42)
        symbols.setSourceFileID(fileID, for: id)
        #expect(symbols.sourceFileID(for: id) == fileID)
    }

    @Test
    func testSourceFileIDReturnsNilForUnset() {
        let symbols = SymbolTable()
        #expect(symbols.sourceFileID(for: SymbolID(rawValue: 0)) == nil)
    }
}

// MARK: - BindingTable Tests

@Suite
struct BindingTableTests {
    @Test
    func testBindExprType() {
        let bindings = BindingTable()
        let types = TypeSystem()
        let expr = ExprID(rawValue: 0)
        let intType = types.make(.primitive(.int, .nonNull))
        bindings.bindExprType(expr, type: intType)
        #expect(bindings.exprTypes[expr] == intType)
    }

    @Test
    func testBindIdentifier() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 0)
        let sym = SymbolID(rawValue: 5)
        bindings.bindIdentifier(expr, symbol: sym)
        #expect(bindings.identifierSymbols[expr] == sym)
    }

    @Test
    func testBindCall() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 0)
        let binding = CallBinding(
            chosenCallee: SymbolID(rawValue: 1),
            substitutedTypeArguments: [],
            parameterMapping: [0: 0]
        )
        bindings.bindCall(expr, binding: binding)
        #expect(bindings.callBindings[expr] != nil)
        #expect(bindings.callBindings[expr]?.chosenCallee == SymbolID(rawValue: 1))
    }

    @Test
    func testBindDecl() {
        let bindings = BindingTable()
        let decl = DeclID(rawValue: 0)
        let sym = SymbolID(rawValue: 3)
        bindings.bindDecl(decl, symbol: sym)
        #expect(bindings.declSymbols[decl] == sym)
    }

    @Test
    func testMarkSuperCall() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 7)
        bindings.markSuperCall(expr)
        #expect(bindings.superCallExprs.contains(expr))
    }

    @Test
    func testMarkSuperCallIdempotent() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 7)
        bindings.markSuperCall(expr)
        bindings.markSuperCall(expr)
        #expect(bindings.superCallExprs.count == 1)
    }

    @Test
    func testMultipleBindings() {
        let bindings = BindingTable()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        bindings.bindExprType(ExprID(rawValue: 0), type: intType)
        bindings.bindExprType(ExprID(rawValue: 1), type: stringType)

        #expect(bindings.exprTypes.count == 2)
        #expect(bindings.exprTypes[ExprID(rawValue: 0)] == intType)
        #expect(bindings.exprTypes[ExprID(rawValue: 1)] == stringType)
    }
}

// MARK: - Scope Tests

@Suite
struct ScopeTests {
    @Test
    func testBaseScopeLookupReturnsLocalSymbol() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = FileScope(parent: nil, symbols: symbols)

        let name = interner.intern("x")
        let id = symbols.define(kind: .local, name: name, fqName: [name], declSite: nil, visibility: .internal)
        scope.insert(id)

        let result = scope.lookup(name)
        #expect(result == [id])
    }

    @Test
    func testBaseScopeLookupDelegatesToParent() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let parent = FileScope(parent: nil, symbols: symbols)
        let child = FunctionScope(parent: parent, symbols: symbols)

        let name = interner.intern("x")
        let id = symbols.define(kind: .local, name: name, fqName: [name], declSite: nil, visibility: .internal)
        parent.insert(id)

        let result = child.lookup(name)
        #expect(result == [id])
    }

    @Test
    func testBaseScopeLocalShadowsParent() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let parent = FileScope(parent: nil, symbols: symbols)
        let child = FunctionScope(parent: parent, symbols: symbols)

        let name = interner.intern("x")
        let parentID = symbols.define(kind: .local, name: name, fqName: [interner.intern("outer"), name], declSite: nil, visibility: .internal)
        let childID = symbols.define(kind: .local, name: name, fqName: [interner.intern("inner"), name], declSite: nil, visibility: .internal)
        parent.insert(parentID)
        child.insert(childID)

        let result = child.lookup(name)
        #expect(result == [childID])
    }

    @Test
    func testBaseScopeLookupReturnsEmptyForUnknown() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = FileScope(parent: nil, symbols: symbols)
        #expect(scope.lookup(interner.intern("unknown")) == [])
    }

    @Test
    func testInsertWithAlias() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = ImportScope(parent: nil, symbols: symbols)

        let originalName = interner.intern("Original")
        let alias = interner.intern("Alias")
        let id = symbols.define(kind: .class, name: originalName, fqName: [originalName], declSite: nil, visibility: .public)
        scope.insertWithAlias(id, asName: alias)

        #expect(scope.lookup(alias) == [id])
        #expect(scope.lookup(originalName) == [])
    }

    @Test
    func testInsertDeduplicates() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = FileScope(parent: nil, symbols: symbols)

        let name = interner.intern("x")
        let id = symbols.define(kind: .local, name: name, fqName: [name], declSite: nil, visibility: .internal)
        scope.insert(id)
        scope.insert(id)

        #expect(scope.lookup(name) == [id])
    }

    @Test
    func testClassMemberScopeReceiverType() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let ownerSym = symbols.define(kind: .class, name: interner.intern("C"), fqName: [interner.intern("C")], declSite: nil, visibility: .public)
        let thisType = types.make(.classType(ClassType(classSymbol: ownerSym)))

        let scope = ClassMemberScope(parent: nil, symbols: symbols, ownerSymbol: ownerSym, thisType: thisType)
        #expect(scope.receiverType == thisType)
        #expect(scope.owner == ownerSym)
    }

    @Test
    func testClassMemberScopeNilReceiverType() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let ownerSym = symbols.define(kind: .object, name: interner.intern("O"), fqName: [interner.intern("O")], declSite: nil, visibility: .public)
        let scope = ClassMemberScope(parent: nil, symbols: symbols, ownerSymbol: ownerSym, thisType: nil)
        #expect(scope.receiverType == nil)
    }

    @Test
    func testInsertWithInvalidIDIsNoOp() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = FileScope(parent: nil, symbols: symbols)
        scope.insert(SymbolID.invalid)
        #expect(scope.lookup(interner.intern("anything")).isEmpty,
                "inserting SymbolID.invalid must leave scope state unchanged")
    }
}

// MARK: - SemaModule Tests

@Suite
struct SemaModuleTests {
    @Test
    func testSemaModuleInit() {
        let (sema, symbols, types, _) = makeSemaModule()
        #expect(sema.symbols === symbols)
        #expect(sema.types === types)
        #expect(sema.bindings.exprTypes.isEmpty)
        #expect(sema.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func testSemaModuleImportedInlineFunctionsDefault() {
        let (sema, _, _, _) = makeSemaModule()
        #expect(sema.importedInlineFunctions.isEmpty)
    }
}

// MARK: - FunctionSignature Tests

@Suite
struct FunctionSignatureTests {
    @Test
    func testFunctionSignatureDefaults() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let sig = FunctionSignature(parameterTypes: [intType], returnType: intType)
        #expect(sig.receiverType == nil)
        #expect(sig.isSuspend == false)
        #expect(sig.valueParameterSymbols.isEmpty)
        #expect(sig.valueParameterHasDefaultValues.isEmpty)
        #expect(sig.valueParameterIsVararg.isEmpty)
        #expect(sig.typeParameterSymbols.isEmpty)
        #expect(sig.reifiedTypeParameterIndices.isEmpty)
        #expect(sig.typeParameterUpperBounds.isEmpty)
    }

    @Test
    func testFunctionSignatureFullInit() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let sig = FunctionSignature(
            receiverType: intType,
            parameterTypes: [intType],
            returnType: intType,
            isSuspend: true,
            valueParameterSymbols: [SymbolID(rawValue: 0)],
            valueParameterHasDefaultValues: [true],
            valueParameterIsVararg: [false],
            typeParameterSymbols: [SymbolID(rawValue: 1)],
            reifiedTypeParameterIndices: [0],
            typeParameterUpperBounds: [intType]
        )
        #expect(sig.receiverType == intType)
        #expect(sig.isSuspend)
        #expect(sig.valueParameterSymbols.count == 1)
        #expect(sig.valueParameterHasDefaultValues == [true])
        #expect(sig.valueParameterIsVararg == [false])
        #expect(sig.typeParameterSymbols.count == 1)
        #expect(sig.reifiedTypeParameterIndices == [0])
        #expect(sig.typeParameterUpperBounds == [intType])
    }

    @Test
    func testFunctionSignatureRetainsMultipleUpperBoundsList() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let sig = FunctionSignature(
            parameterTypes: [intType],
            returnType: intType,
            typeParameterSymbols: [SymbolID(rawValue: 1), SymbolID(rawValue: 2)],
            typeParameterUpperBoundsList: [[intType, boolType], []]
        )

        #expect(sig.typeParameterUpperBoundsList == [[intType, boolType], []])
        #expect(sig.typeParameterUpperBounds == [intType, nil])
    }
}

// MARK: - CallBinding Tests

@Suite
struct CallBindingTests {
    @Test
    func testCallBindingInit() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let binding = CallBinding(
            chosenCallee: SymbolID(rawValue: 0),
            substitutedTypeArguments: [intType],
            parameterMapping: [0: 0, 1: 1]
        )
        #expect(binding.chosenCallee == SymbolID(rawValue: 0))
        #expect(binding.substitutedTypeArguments == [intType])
        #expect(binding.parameterMapping == [0: 0, 1: 1])
    }
}
