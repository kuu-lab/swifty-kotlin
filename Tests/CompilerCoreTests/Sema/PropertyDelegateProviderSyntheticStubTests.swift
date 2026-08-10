#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct PropertyDelegateProviderSyntheticStubTests {
    @Test
    func testPropertyDelegateProviderSyntheticStubTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.properties.PropertyDelegateProvider
            import kotlin.reflect.KProperty

            class ResourceDelegate {
                operator fun getValue(thisRef: Any?, property: KProperty<*>): String = "value"
            }

            fun provider(): PropertyDelegateProvider<Any?, ResourceDelegate> =
                PropertyDelegateProvider<Any?, ResourceDelegate> { thisRef, property -> ResourceDelegate() }

            val resource by provider()
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let path0 = paths[0]
            let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
            #expect(
                !path0Diagnostics.contains(where: { $0.severity == .error }),
                "Unexpected diagnostics: \(path0Diagnostics)"
            )

            // === testPropertyDelegateProviderSurfaceIsRegistered ===
            do {

                let propertiesFQName = ["kotlin", "properties"].map { interner.intern($0) }
                let providerFQName = propertiesFQName + [interner.intern("PropertyDelegateProvider")]
                let kPropertyFQName = ["kotlin", "reflect", "KProperty"].map { interner.intern($0) }

                let providerSymbol = try #require(sema.symbols.lookup(fqName: providerFQName))
                let providerInfo = try #require(sema.symbols.symbol(providerSymbol))
                #expect(providerInfo.kind == .interface)
                #expect(providerInfo.flags.contains(.funInterface))
                #expect(providerInfo.flags.contains(.synthetic))

                let typeParameters = sema.types.nominalTypeParameterSymbols(for: providerSymbol)
                #expect(try resolvedNames(typeParameters, sema: sema, interner: interner) == ["T", "D"])
                #expect(sema.types.nominalTypeParameterVariances(for: providerSymbol) == [.in, .out])

                let thisRefType = sema.types.make(.typeParam(TypeParamType(
                    symbol: typeParameters[0],
                    nullability: .nonNull
                )))
                let delegateType = sema.types.make(.typeParam(TypeParamType(
                    symbol: typeParameters[1],
                    nullability: .nonNull
                )))
                let providerType = sema.types.make(.classType(ClassType(
                    classSymbol: providerSymbol,
                    args: [.invariant(thisRefType), .invariant(delegateType)],
                    nullability: .nonNull
                )))
                let kPropertySymbol = try #require(sema.symbols.lookup(fqName: kPropertyFQName))
                let kPropertyType = sema.types.make(.classType(ClassType(
                    classSymbol: kPropertySymbol,
                    args: [.star],
                    nullability: .nonNull
                )))

                let provideSymbol = try #require(sema.symbols.lookup(fqName: providerFQName + [interner.intern("provideDelegate")]))
                let provideInfo = try #require(sema.symbols.symbol(provideSymbol))
                #expect(provideInfo.kind == .function)
                #expect(provideInfo.flags.isSuperset(of: [.abstractType, .operatorFunction, .synthetic]))

                let signature = try #require(sema.symbols.functionSignature(for: provideSymbol))
                #expect(signature.receiverType == providerType)
                #expect(signature.parameterTypes == [thisRefType, kPropertyType])
                #expect(signature.returnType == delegateType)
                #expect(signature.typeParameterSymbols == typeParameters)
                #expect(signature.classTypeParameterCount == 2)
            }

            // === testProviderReturnTypeFeedsDelegatedPropertyInference ===
            do {

                let sampleFQName = [interner.intern("sample0")]
                let resourceSymbol = try #require(sema.symbols.lookup(fqName: sampleFQName + [interner.intern("resource")]))
                #expect(sema.symbols.propertyType(for: resourceSymbol) == sema.types.stringType)
                #expect(sema.symbols.hasProvideDelegate(for: resourceSymbol))

                let provideSymbol = try #require(sema.symbols.delegateProvideDelegateSymbol(for: resourceSymbol))
                let provideInfo = try #require(sema.symbols.symbol(provideSymbol))
                #expect(interner.resolve(provideInfo.name) == "provideDelegate")
                #expect(provideInfo.flags.contains(.operatorFunction))

                let getValueSymbol = try #require(sema.symbols.delegateGetValueSymbol(for: resourceSymbol))
                let getValueInfo = try #require(sema.symbols.symbol(getValueSymbol))
                #expect(interner.resolve(getValueInfo.name) == "getValue")
            }
        }
    }

    private func resolvedNames(
        _ symbols: [SymbolID],
        sema: SemaModule,
        interner: StringInterner
    ) throws -> [String] {
        try symbols.map { symbol in
            try interner.resolve(#require(sema.symbols.symbol(symbol)?.name))
        }
    }
}
#endif
