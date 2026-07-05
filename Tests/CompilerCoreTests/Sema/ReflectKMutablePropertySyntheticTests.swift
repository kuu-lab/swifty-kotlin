#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKMutablePropertySyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected KMutableProperty surface to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKMutablePropertySurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }

        let kPropertySymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty")]
        ))
        let kMutablePropertySymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty")]
        ))

        let kMutablePropertyInfo = try #require(sema.symbols.symbol(kMutablePropertySymbol))
        #expect(kMutablePropertyInfo.kind == .interface)
        #expect(kMutablePropertyInfo.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kMutablePropertySymbol)
        #expect(typeParams.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: kMutablePropertySymbol) == [.invariant])

        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        #expect(sema.symbols.directSupertypes(for: kMutablePropertySymbol).contains(kPropertySymbol))
        #expect(
            sema.symbols.supertypeTypeArgs(for: kMutablePropertySymbol, supertype: kPropertySymbol) == [.invariant(valueType)]
        )
    }

    @Test func testKMutablePropertyTypeReferencesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KMutableProperty

        fun <V> propertyName(property: KMutableProperty<V>): String = property.name
        """

        _ = try makeSema(source: source)
    }

    @Test func testKMutablePropertySetterNestedTypeIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }

        let kMutablePropertySymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty")]
        ))
        let setterSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty"), interner.intern("Setter")]
        ))

        let setterInfo = try #require(sema.symbols.symbol(setterSymbol))
        #expect(setterInfo.kind == .interface)
        #expect(setterInfo.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: setterSymbol)
        #expect(typeParams.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: setterSymbol) == [.invariant])

        // Setter should be a child of KMutableProperty.
        #expect(sema.symbols.parentSymbol(for: setterSymbol) == kMutablePropertySymbol)
    }

    @Test func testKMutablePropertySetterPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }

        let kMutablePropertySymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty")]
        ))
        let setterSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty"), interner.intern("Setter")]
        ))

        let setterPropSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty"), interner.intern("setter")]
        ))
        let setterPropInfo = try #require(sema.symbols.symbol(setterPropSymbol))
        #expect(setterPropInfo.kind == .property)
        #expect(setterPropInfo.flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: setterPropSymbol) == kMutablePropertySymbol)

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kMutablePropertySymbol)
        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        let expectedSetterType = sema.types.make(.classType(ClassType(
            classSymbol: setterSymbol,
            args: [.invariant(valueType)],
            nullability: .nonNull
        )))
        #expect(sema.symbols.propertyType(for: setterPropSymbol) == expectedSetterType)
    }

    @Test func testKMutablePropertySetterAccessResolvesInSource() throws {
        let source = """
        import kotlin.reflect.KMutableProperty

        fun <V> getSetter(property: KMutableProperty<V>): KMutableProperty.Setter<V> = property.setter
        """

        _ = try makeSema(source: source)
    }
}
#endif
