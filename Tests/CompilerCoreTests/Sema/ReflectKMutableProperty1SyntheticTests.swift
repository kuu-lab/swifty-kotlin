#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKMutableProperty1SyntheticTests {

    @Test
    func testReflectKMutableProperty1SyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.reflect.KMutableProperty1

            fun <T, V> write(property: KMutableProperty1<T, V>, receiver: T, value: V) {
                property.set(receiver, value)
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testKMutableProperty1SurfaceIsRegistered ===
            do {

                let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }

                let kProperty1Symbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KProperty1")]
                ))
                let kMutablePropertySymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KMutableProperty")]
                ))
                let kMutableProperty1Symbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KMutableProperty1")]
                ))

                let kMutableProperty1Info = try #require(sema.symbols.symbol(kMutableProperty1Symbol))
                #expect(kMutableProperty1Info.kind == .interface)
                // KSP-682: KMutableProperty1 is now bundled Kotlin source, not a synthetic stub.
                #expect(!kMutableProperty1Info.flags.contains(.synthetic))

                let typeParams = sema.types.nominalTypeParameterSymbols(for: kMutableProperty1Symbol)
                #expect(typeParams.count == 2)
                #expect(sema.types.nominalTypeParameterVariances(for: kMutableProperty1Symbol) == [.invariant, .invariant])

                let receiverTypeParam = sema.types.make(.typeParam(TypeParamType(
                    symbol: typeParams[0],
                    nullability: .nonNull
                )))
                let valueType = sema.types.make(.typeParam(TypeParamType(
                    symbol: typeParams[1],
                    nullability: .nonNull
                )))
                // KSP-682: source declares `KMutableProperty1<T, V> : KProperty1<T, V>,
                // KMutableProperty<V>`, so Function1 is a transitive supertype via
                // KProperty1 rather than a direct one (matching Kotlin).
                let supertypes = sema.symbols.directSupertypes(for: kMutableProperty1Symbol)
                #expect(supertypes.contains(kProperty1Symbol))
                #expect(supertypes.contains(kMutablePropertySymbol))
                #expect(
                    sema.symbols.supertypeTypeArgs(for: kMutableProperty1Symbol, supertype: kProperty1Symbol) == [.invariant(receiverTypeParam), .invariant(valueType)]
                )
                #expect(
                    sema.symbols.supertypeTypeArgs(for: kMutableProperty1Symbol, supertype: kMutablePropertySymbol) == [.invariant(valueType)]
                )

                let setSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KMutableProperty1"), interner.intern("set")]
                ))
                let setSignature = try #require(sema.symbols.functionSignature(for: setSymbol))
                let receiverType = sema.types.make(.classType(ClassType(
                    classSymbol: kMutableProperty1Symbol,
                    args: [.invariant(receiverTypeParam), .invariant(valueType)],
                    nullability: .nonNull
                )))
                #expect(setSignature.receiverType == receiverType)
                #expect(setSignature.parameterTypes == [receiverTypeParam, valueType])
                #expect(setSignature.returnType == sema.types.unitType)
                #expect(setSignature.typeParameterSymbols == typeParams)
                #expect(setSignature.classTypeParameterCount == 2)
            }

            // === testKMutableProperty1SetResolvesInSource ===
            do {
                let path0 = paths[0]
                let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
                #expect(!path0Diagnostics.contains(where: { $0.severity == .error }), "Expected testKMutableProperty1SetResolvesInSource to resolve cleanly, got: \(path0Diagnostics)")
            }
        }
    }

}
#endif
