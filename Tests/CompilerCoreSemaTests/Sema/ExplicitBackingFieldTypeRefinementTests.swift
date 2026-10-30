#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing
import TestStdlibCache

@Suite
struct ExplicitBackingFieldTypeRefinementTests {
    @Test
    func refinesPropertyReadsFromAnInferredValBackingFieldType() throws {
        let ctx = makeContext("""
        val items: List<String>
            field = mutableListOf()

        fun append(): String {
            items.add("OK")
            return items.last()
        }
        """)
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let property = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("items")]))
        let declaredType = try #require(sema.symbols.propertyType(for: property))
        let backingField = try #require(sema.symbols.backingFieldSymbol(for: property))
        let backingFieldType = try #require(sema.symbols.propertyType(for: backingField))
        let ast = try #require(ctx.ast)
        let backingInitializerType = ast.files
            .flatMap(\.topLevelDecls)
            .compactMap { declID -> TypeID? in
                guard case let .propertyDecl(property)? = ast.arena.decl(declID),
                      let explicitField = property.explicitBackingField,
                      let initializer = explicitField.initializer
                else {
                    return nil
                }
                return sema.bindings.exprType(for: initializer)
            }
        let itemReadTypes = ast.arena.exprs.indices.compactMap { rawID -> TypeID? in
            let id = ExprID(rawValue: Int32(rawID))
            guard case let .nameRef(name, _)? = ast.arena.expr(id),
                  name == ctx.interner.intern("items")
            else {
                return nil
            }
            return sema.bindings.exprType(for: id)
        }

        #expect(
            !ctx.diagnostics.hasError,
            "errors=\(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.message)); declared=\(sema.types.renderType(declaredType)); storage=\(sema.types.renderType(backingFieldType)); initializer=\(backingInitializerType.map(sema.types.renderType)); reads=\(itemReadTypes.map(sema.types.renderType))"
        )

        #expect(className(of: declaredType, sema: sema, interner: ctx.interner) == ["kotlin", "collections", "List"])
        #expect(className(of: backingFieldType, sema: sema, interner: ctx.interner) == ["kotlin", "collections", "MutableList"])
        #expect(sema.types.renderType(backingFieldType).contains("String"))

        #expect(itemReadTypes.count == 2)
        #expect(itemReadTypes.allSatisfy { $0 == backingFieldType })
    }

    @Test
    func doesNotRefineMutablePropertiesOrReadOnlyListValues() throws {
        let ctx = makeContext("""
        var mutableItems: List<String>
            field = mutableListOf()

        val readOnlyItems: List<String>
            field = listOf()

        fun rejectMutablePropertyWrite() { mutableItems.add("NO") }
        fun rejectReadOnlyInitializerWrite() { readOnlyItems.add("NO") }
        fun rejectListParameterWrite(items: List<String>) { items.add("NO") }
        """)
        try runSema(ctx)
        let unresolvedAddDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0024"
        }
        #expect(unresolvedAddDiagnostics.count == 3, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func keepsTheBackingInitializerGenericTypeNarrowerThanThePublicPropertyType() throws {
        let ctx = makeContext("""
        val items: List<Any>
            field = mutableListOf("OK")

        fun rejectWidenedElement() { items.add(Any()) }
        """)
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let property = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("items")]))
        let declaredType = try #require(sema.symbols.propertyType(for: property))
        let backingField = try #require(sema.symbols.backingFieldSymbol(for: property))
        let backingFieldType = try #require(sema.symbols.propertyType(for: backingField))

        #expect(className(of: declaredType, sema: sema, interner: ctx.interner) == ["kotlin", "collections", "List"])
        #expect(sema.types.renderType(declaredType).contains("Any"))
        #expect(className(of: backingFieldType, sema: sema, interner: ctx.interner) == ["kotlin", "collections", "MutableList"])
        #expect(sema.types.renderType(backingFieldType).contains("String"))
        #expect(ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    private func className(
        of type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String]? {
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }
        return symbol.fqName.map(interner.resolve)
    }

    private func makeContext(_ source: String) -> CompilationContext {
        TestStdlibCache.shared.prepare()
        return makeContextFromSource(source, allowDefaultStdlibLibrary: true)
    }
}
#endif
