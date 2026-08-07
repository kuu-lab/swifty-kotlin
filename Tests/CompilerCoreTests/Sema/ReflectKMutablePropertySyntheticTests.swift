#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKMutablePropertySyntheticTests {

    @Test
    func testReflectKMutablePropertySyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.reflect.KMutableProperty

            fun <V> propertyName(property: KMutableProperty<V>): String = property.name
            """,
            """
            package sample1
            import kotlin.reflect.KMutableProperty

            fun <V> getSetter(property: KMutableProperty<V>): KMutableProperty.Setter<V> = property.setter
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testKMutablePropertySurfaceIsRegistered ===
            do {

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

            // === testKMutablePropertySetterNestedTypeIsRegistered ===
            do {

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

            // === testKMutablePropertySetterPropertyIsRegistered ===
            do {

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

            // === testKMutablePropertyTypeReferencesResolveInSource ===
            do {
                let path0 = paths[0]
                let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
                #expect(!path0Diagnostics.contains(where: { $0.severity == .error }), "Expected testKMutablePropertyTypeReferencesResolveInSource to resolve cleanly, got: \(path0Diagnostics)")
            }

            // === testKMutablePropertySetterAccessResolvesInSource ===
            do {
                let path1 = paths[1]
                let path1Diagnostics = diagnosticsForPath(path1, in: ctx)
                #expect(!path1Diagnostics.contains(where: { $0.severity == .error }), "Expected testKMutablePropertySetterAccessResolvesInSource to resolve cleanly, got: \(path1Diagnostics)")
            }
        }
    }

}
#endif
