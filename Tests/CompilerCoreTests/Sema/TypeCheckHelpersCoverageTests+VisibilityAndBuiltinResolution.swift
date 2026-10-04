@testable import CompilerCore
import Testing

extension TypeCheckHelpersCoverageTests {
    @Test
    func testEmitVisibilityErrorAndBindErrorType() throws {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()

        let privateSymbolID = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("privateFn"),
            fqName: [fixture.interner.intern("privateFn")],
            declSite: makeRange(),
            visibility: .private
        )
        let protectedSymbolID = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("protectedFn"),
            fqName: [fixture.interner.intern("protectedFn")],
            declSite: makeRange(),
            visibility: .protected
        )

        let privateSymbol = fixture.symbols.symbol(privateSymbolID)
        let protectedSymbol = fixture.symbols.symbol(protectedSymbolID)

        helpers.emitVisibilityError(
            for: try #require(privateSymbol),
            name: "privateFn",
            range: makeRange(),
            diagnostics: fixture.diagnostics
        )
        helpers.emitVisibilityError(
            for: try #require(protectedSymbol),
            name: "protectedFn",
            range: makeRange(),
            diagnostics: fixture.diagnostics
        )

        #expect(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" })
        #expect(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0041" })

        let exprID = ExprID(rawValue: 123)
        let result = helpers.bindAndReturnErrorType(exprID, sema: fixture.sema)
        #expect(result == fixture.types.errorType)
        #expect(fixture.bindings.exprType(for: exprID) == fixture.types.errorType)
    }

    @Test
    func testStableLocalSymbolIterableAndBuiltinReturnTypes() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()

        let stableLocal = fixture.symbols.define(
            kind: .local,
            name: fixture.interner.intern("stable"),
            fqName: [fixture.interner.intern("stable")],
            declSite: nil,
            visibility: .private
        )
        let mutableLocal = fixture.symbols.define(
            kind: .local,
            name: fixture.interner.intern("mutable"),
            fqName: [fixture.interner.intern("mutable")],
            declSite: nil,
            visibility: .private,
            flags: [.mutable]
        )
        let fnSymbol = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("f"),
            fqName: [fixture.interner.intern("f")],
            declSite: nil,
            visibility: .public
        )

        #expect(helpers.isStableLocalSymbol(stableLocal, sema: fixture.sema))
        #expect(!(helpers.isStableLocalSymbol(mutableLocal, sema: fixture.sema)))
        #expect(!(helpers.isStableLocalSymbol(fnSymbol, sema: fixture.sema)))
        #expect(!(helpers.isStableLocalSymbol(SymbolID(rawValue: 999), sema: fixture.sema)))

        let intArraySymbol = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("IntArray"),
            fqName: [fixture.interner.intern("IntArray")],
            declSite: nil,
            visibility: .public
        )
        let intArrayType = fixture.types.make(
            .classType(ClassType(classSymbol: intArraySymbol, args: [], nullability: .nonNull))
        )

        #expect(
            helpers.arrayElementType(for: intArrayType, sema: fixture.sema, interner: fixture.interner) ==
            fixture.types.intType
        )
        #expect(
            helpers.arrayElementType(for: fixture.types.intType, sema: fixture.sema, interner: fixture.interner) == nil
        )

        #expect(
            helpers.iterableElementType(for: fixture.types.intType, isRangeExpr: true, sema: fixture.sema, interner: fixture.interner) ==
            fixture.types.intType
        )
        #expect(
            helpers.iterableElementType(for: intArrayType, isRangeExpr: false, sema: fixture.sema, interner: fixture.interner) ==
            fixture.types.intType
        )

        #expect(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("runBlocking"),
                argumentCount: 1,
                sema: fixture.sema,
                interner: fixture.interner
            ) ==
            fixture.types.anyType
        )
        #expect(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("launch"),
                argumentCount: 1,
                sema: fixture.sema,
                interner: fixture.interner
            ) ==
            fixture.types.anyType
        )
        #expect(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("kk_array_get"),
                argumentCount: 2,
                sema: fixture.sema,
                interner: fixture.interner
            ) ==
            fixture.types.anyType
        )
        #expect(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("__kk_list_get"),
                argumentCount: 2,
                sema: fixture.sema,
                interner: fixture.interner
            ) ==
            fixture.types.anyType
        )
        #expect(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("unknown"),
                argumentCount: 1,
                sema: fixture.sema,
                interner: fixture.interner
            ) == nil
        )
        #expect(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: nil,
                argumentCount: 1,
                sema: fixture.sema,
                interner: fixture.interner
            ) == nil
        )
    }

    @Test
    func testResolveBuiltinAndTypeRefVariants() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()

        #expect(
            helpers.resolveBuiltinTypeName(fixture.interner.intern("Int"), types: fixture.types, interner: fixture.interner) ==
            fixture.types.intType
        )
        #expect(
            helpers.resolveBuiltinTypeName(
                fixture.interner.intern("Any"),
                nullability: .nullable,
                types: fixture.types,
                interner: fixture.interner
            ) ==
            fixture.types.nullableAnyType
        )
        #expect(
            helpers.resolveBuiltinTypeName(
                fixture.interner.intern("Nothing"),
                nullability: .nullable,
                types: fixture.types,
                interner: fixture.interner
            ) ==
            fixture.types.nullableNothingType
        )
        #expect(helpers.resolveBuiltinTypeName(fixture.interner.intern("Unknown"), types: fixture.types, interner: fixture.interner) == nil)

        let intRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("Int")], args: [], nullable: false)
        )
        let nullableIntRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("Int")], args: [], nullable: true)
        )
        let fnRef = fixture.astArena.appendTypeRef(
            .functionType(contextReceivers: [], receiver: nil, params: [intRef], returnType: nullableIntRef, isSuspend: true, nullable: false)
        )
        let intersectionRef = fixture.astArena.appendTypeRef(.intersection(parts: [intRef, nullableIntRef]))

        #expect(
            helpers.resolveTypeRef(intRef, ast: fixture.ast, sema: fixture.sema, interner: fixture.interner) ==
            fixture.types.intType
        )

        let resolvedFn = helpers.resolveTypeRef(fnRef, ast: fixture.ast, sema: fixture.sema, interner: fixture.interner)
        if case let .functionType(ft) = fixture.types.kind(of: resolvedFn) {
            #expect(ft.params == [fixture.types.intType])
            #expect(ft.returnType == fixture.types.make(.primitive(.int, .nullable)))
            #expect(ft.isSuspend)
        } else {
            Issue.record("Expected functionType")
        }

        let resolvedIntersection = helpers.resolveTypeRef(
            intersectionRef,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner
        )
        if case let .intersection(parts) = fixture.types.kind(of: resolvedIntersection) {
            #expect(parts.count == 2)
        } else {
            Issue.record("Expected intersection")
        }

        let unresolvedRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("MissingType")], args: [], nullable: false)
        )
        let unresolved = helpers.resolveTypeRef(
            unresolvedRef,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner,
            diagnostics: fixture.diagnostics
        )
        #expect(unresolved == fixture.types.errorType)
        #expect(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0025" })

        #expect(
            helpers.resolveTypeRef(TypeRefID(rawValue: 9999), ast: fixture.ast, sema: fixture.sema, interner: fixture.interner) ==
            fixture.types.errorType
        )
    }

    @Test
    func testResolveAnnotatedExtensionFunctionTypeVariants() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()

        let function2Name = fixture.interner.intern("Function2")
        _ = fixture.symbols.define(
            kind: .class,
            name: function2Name,
            fqName: [function2Name],
            declSite: nil,
            visibility: .public
        )
        let listName = fixture.interner.intern("List")
        _ = fixture.symbols.define(
            kind: .class,
            name: listName,
            fqName: [listName],
            declSite: nil,
            visibility: .public
        )

        let intRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("Int")], args: [], nullable: false)
        )
        let function2Ref = fixture.astArena.appendTypeRef(
            .named(
                path: [function2Name],
                args: [.invariant(intRef), .invariant(intRef), .invariant(intRef)],
                nullable: false
            )
        )
        let annotatedFunction2Ref = fixture.astArena.appendTypeRef(
            .annotated(base: function2Ref, annotations: [AnnotationNode(name: "ExtensionFunctionType")])
        )

        let resolved = helpers.resolveTypeRef(
            annotatedFunction2Ref,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner,
            diagnostics: fixture.diagnostics
        )

        if case let .functionType(ft) = fixture.types.kind(of: resolved) {
            #expect(ft.receiver == fixture.types.intType)
            #expect(ft.params == [fixture.types.intType])
            #expect(ft.returnType == fixture.types.intType)
            #expect(!(ft.isSuspend))
            #expect(ft.nullability == .nonNull)
        } else {
            Issue.record("Expected extension function type to normalize to functionType")
        }

        let listRef = fixture.astArena.appendTypeRef(
            .named(path: [listName], args: [.invariant(intRef)], nullable: false)
        )
        let annotatedListRef = fixture.astArena.appendTypeRef(
            .annotated(base: listRef, annotations: [AnnotationNode(name: "ExtensionFunctionType")])
        )
        let invalidResult = helpers.resolveTypeRef(
            annotatedListRef,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner,
            diagnostics: fixture.diagnostics
        )

        #expect(invalidResult == fixture.types.errorType)
        #expect(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-EXTFN-TYPE" })
    }
}
