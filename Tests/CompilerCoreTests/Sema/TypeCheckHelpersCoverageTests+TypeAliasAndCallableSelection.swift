@testable import CompilerCore
import Testing

extension TypeCheckHelpersCoverageTests {
    @Test
    func testTypeAliasExpansionAndSubstitutionPaths() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()

        let tParam = fixture.symbols.define(
            kind: .typeParameter,
            name: fixture.interner.intern("T"),
            fqName: [fixture.interner.intern("Alias"), fixture.interner.intern("T")],
            declSite: nil,
            visibility: .private
        )
        let aliasSymbol = fixture.symbols.define(
            kind: .typeAlias,
            name: fixture.interner.intern("Alias"),
            fqName: [fixture.interner.intern("pkg"), fixture.interner.intern("Alias")],
            declSite: nil,
            visibility: .public
        )
        let typeParamType = fixture.types.make(.typeParam(TypeParamType(symbol: tParam, nullability: .nonNull)))
        fixture.symbols.setTypeAliasUnderlyingType(typeParamType, for: aliasSymbol)
        fixture.symbols.setTypeAliasTypeParameters([tParam], for: aliasSymbol)

        let expanded = helpers.expandTypeAlias(
            aliasSymbol,
            typeArgs: [.invariant(fixture.types.intType)],
            sema: fixture.sema,
            visited: [],
            depth: 0,
            diagnostics: fixture.diagnostics
        )
        #expect(expanded == fixture.types.intType)

        let aliasRef = fixture.astArena.appendTypeRef(
            .named(
                path: [fixture.interner.intern("Alias")],
                args: [.invariant(fixture.astArena.appendTypeRef(.named(path: [fixture.interner.intern("Int")], args: [], nullable: false)))],
                nullable: false
            )
        )
        let resolvedAlias = helpers.resolveTypeRef(
            aliasRef,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner,
            diagnostics: fixture.diagnostics
        )
        #expect(resolvedAlias == fixture.types.intType)

        let aliasA = fixture.symbols.define(
            kind: .typeAlias,
            name: fixture.interner.intern("A"),
            fqName: [fixture.interner.intern("A")],
            declSite: nil,
            visibility: .public
        )
        let aliasB = fixture.symbols.define(
            kind: .typeAlias,
            name: fixture.interner.intern("B"),
            fqName: [fixture.interner.intern("B")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setTypeAliasUnderlyingType(
            fixture.types.make(.classType(ClassType(classSymbol: aliasB, args: [], nullability: .nonNull))),
            for: aliasA
        )
        fixture.symbols.setTypeAliasUnderlyingType(
            fixture.types.make(.classType(ClassType(classSymbol: aliasA, args: [], nullability: .nonNull))),
            for: aliasB
        )

        let cyclic = helpers.expandTypeAlias(
            aliasA,
            typeArgs: [],
            sema: fixture.sema,
            visited: [],
            depth: 0,
            diagnostics: fixture.diagnostics
        )
        #expect(cyclic == nil)
        #expect(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ALIAS-CYCLE" })

        let overDepth = helpers.expandTypeAlias(
            aliasA,
            typeArgs: [],
            sema: fixture.sema,
            visited: [],
            depth: 32,
            diagnostics: fixture.diagnostics
        )
        #expect(overDepth == nil)
        #expect(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ALIAS-DEPTH" })

        _ = helpers.expandTypeAlias(
            aliasSymbol,
            typeArgs: [],
            sema: fixture.sema,
            visited: [],
            depth: 0,
            diagnostics: fixture.diagnostics
        )
        #expect(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0062" })

        let substituted = helpers.applyAliasSubstitution(
            typeParamType,
            argSubstitution: [tParam: .invariant(fixture.types.stringType)],
            sema: fixture.sema
        )
        #expect(substituted == fixture.types.stringType)
    }

    @Test
    func testSubstituteAliasArgAndNullabilityHelpers() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()
        let range = makeRange()

        let tp = fixture.symbols.define(
            kind: .typeParameter,
            name: fixture.interner.intern("U"),
            fqName: [fixture.interner.intern("U")],
            declSite: nil,
            visibility: .private
        )
        let tpType = fixture.types.make(.typeParam(TypeParamType(symbol: tp, nullability: .nullable)))

        let substitutedInvariant = helpers.substituteAliasArg(
            .invariant(tpType),
            argSubstitution: [tp: .invariant(fixture.types.intType)],
            sema: fixture.sema
        )
        if case let .invariant(inner) = substitutedInvariant {
            #expect(fixture.types.kind(of: inner) == .primitive(.int, .nullable))
        } else {
            Issue.record("Expected invariant")
        }

        let substitutedOut = helpers.substituteAliasArg(
            .out(tpType),
            argSubstitution: [tp: .star],
            sema: fixture.sema
        )
        #expect(substitutedOut == .star)

        let substitutedIn = helpers.substituteAliasArg(
            .in(tpType),
            argSubstitution: [tp: .in(fixture.types.stringType)],
            sema: fixture.sema
        )
        if case let .in(inner) = substitutedIn {
            #expect(fixture.types.kind(of: inner) == .stringStruct(.nullable))
        } else {
            Issue.record("Expected in")
        }

        #expect(
            helpers.applyNullabilityForTypeCheck(fixture.types.intType, types: fixture.types) ==
            fixture.types.make(.primitive(.int, .nullable))
        )
        #expect(
            helpers.applyNullabilityForTypeCheck(fixture.types.errorType, types: fixture.types) ==
            fixture.types.nullableAnyType
        )
        let nullableKClass = helpers.applyNullabilityForTypeCheck(
            fixture.types.makeKClassType(argument: fixture.types.intType),
            types: fixture.types
        )
        #expect(
            nullableKClass ==
            fixture.types.makeKClassType(argument: fixture.types.intType, nullability: .nullable)
        )

        #expect(helpers.typeArgInnerTypeForCheck(.star) == TypeID.invalid)
        #expect(helpers.typeArgInnerTypeForCheck(.out(fixture.types.intType)) == fixture.types.intType)

        let explicitTypeArgRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("Int")], args: [], nullable: false)
        )
        #expect(
            helpers.resolveExplicitTypeArgs([], ast: fixture.ast, sema: fixture.sema, interner: fixture.interner) ==
            []
        )
        #expect(
            helpers.resolveExplicitTypeArgs([explicitTypeArgRef], ast: fixture.ast, sema: fixture.sema, interner: fixture.interner) ==
            [fixture.types.intType]
        )

        #expect(helpers.isTerminatingExpr(.returnExpr(value: nil, range: range)))
        #expect(helpers.isTerminatingExpr(.throwExpr(value: fixture.astArena.appendExpr(.intLiteral(1, range)), range: range)))
        #expect(!(helpers.isTerminatingExpr(.intLiteral(1, range))))

        #expect(helpers.compoundAssignToBinaryOp(.plusAssign) == .add)
        #expect(helpers.compoundAssignToBinaryOp(.modAssign) == .modulo)
    }

    @Test
    func testMemberCallableSelection() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()
        let range = makeRange()

        let base = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("Base"),
            fqName: [fixture.interner.intern("Base")],
            declSite: nil,
            visibility: .public
        )
        let child = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("Child"),
            fqName: [fixture.interner.intern("Child")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setDirectSupertypes([base], for: child)

        let owner = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("Owner"),
            fqName: [fixture.interner.intern("Owner")],
            declSite: nil,
            visibility: .public
        )
        let receiverType = fixture.types.make(.classType(ClassType(classSymbol: owner, args: [], nullability: .nonNull)))

        let memberFn = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("m"),
            fqName: [fixture.interner.intern("Owner"), fixture.interner.intern("m")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setParentSymbol(owner, for: memberFn)
        fixture.symbols.setFunctionSignature(
            FunctionSignature(receiverType: receiverType, parameterTypes: [], returnType: fixture.types.unitType),
            for: memberFn
        )

        let candidates = helpers.collectMemberFunctionCandidates(
            named: fixture.interner.intern("m"),
            receiverType: receiverType,
            sema: fixture.sema,
            interner: fixture.interner
        )
        #expect(candidates == [memberFn])

        let propertySymbol = fixture.symbols.define(
            kind: .property,
            name: fixture.interner.intern("p"),
            fqName: [fixture.interner.intern("Owner"), fixture.interner.intern("p")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setPropertyType(fixture.types.intType, for: propertySymbol)

        let propertyLookup = helpers.lookupMemberProperty(
            named: fixture.interner.intern("p"),
            receiverType: receiverType,
            sema: fixture.sema
        )
        let propertyLookupSymbol = propertyLookup?.symbol
        #expect(propertyLookupSymbol == propertySymbol)

        #expect(helpers.isNominalSubtype(child, of: base, symbols: fixture.symbols))
        #expect(!(helpers.isNominalSubtype(base, of: child, symbols: fixture.symbols)))

        let calleeExpr = ExprID(rawValue: 700)
        fixture.bindings.bindCallableTarget(calleeExpr, target: .symbol(memberFn))
        #expect(helpers.callableTargetForCalleeExpr(calleeExpr, sema: fixture.sema) == .symbol(memberFn))

        let calleeExpr2 = ExprID(rawValue: 701)
        fixture.bindings.bindIdentifier(calleeExpr2, symbol: propertySymbol)
        #expect(helpers.callableTargetForCalleeExpr(calleeExpr2, sema: fixture.sema) == .localValue(propertySymbol))

        let callableType = helpers.callableFunctionType(
            for: FunctionSignature(receiverType: receiverType, parameterTypes: [fixture.types.intType], returnType: fixture.types.unitType),
            bindReceiver: false,
            sema: fixture.sema
        )
        if case let .functionType(ft) = fixture.types.kind(of: callableType) {
            #expect(ft.params.count == 2)
        } else {
            Issue.record("Expected function type")
        }

        let chooserA = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("choose"),
            fqName: [fixture.interner.intern("chooseA")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [fixture.types.anyType], returnType: fixture.types.anyType),
            for: chooserA
        )
        let chooserB = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("choose"),
            fqName: [fixture.interner.intern("chooseB")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [fixture.types.intType], returnType: fixture.types.intType),
            for: chooserB
        )

        let expectedFnType = fixture.types.make(
            .functionType(FunctionType(params: [fixture.types.intType], returnType: fixture.types.intType, isSuspend: false, nullability: .nonNull))
        )
        let chosen = helpers.chooseCallableReferenceTarget(
            from: [chooserA, chooserB],
            expectedType: expectedFnType,
            bindReceiver: true,
            sema: fixture.sema
        )
        #expect(chosen == chooserB)

        let defaultChosen = helpers.chooseCallableReferenceTarget(
            from: [chooserB, chooserA],
            expectedType: fixture.types.intType,
            bindReceiver: true,
            sema: fixture.sema
        )
        #expect(defaultChosen == [chooserA, chooserB].sorted(by: { $0.rawValue < $1.rawValue }).first)
    }
}
