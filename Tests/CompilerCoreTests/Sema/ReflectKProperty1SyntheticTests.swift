#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKProperty1SyntheticTests {

    @Test
    func testReflectKProperty1SyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.reflect.KProperty1

            fun <T, V> read(property: KProperty1<T, V>, receiver: T): V {
                val first = property.get(receiver)
                val second = property.invoke(receiver)
                return first
            }

            fun <T, V> delegateOf(property: KProperty1<T, V>, receiver: T): Any? =
                property.getDelegate(receiver)
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testKProperty1SurfaceIsRegistered ===
            do {

                let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
                let functionPackage = ["kotlin", "Function"].map { interner.intern($0) }

                let kPropertySymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KProperty")]
                ))
                let kProperty1Symbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KProperty1")]
                ))
                let function1Symbol = try #require(sema.symbols.lookup(
                    fqName: functionPackage + [interner.intern("Function1")]
                ))

                let kProperty1Info = try #require(sema.symbols.symbol(kProperty1Symbol))
                #expect(kProperty1Info.kind == .interface)
                // KSP-682: KProperty1 is now bundled Kotlin source, not a synthetic stub.
                #expect(!kProperty1Info.flags.contains(.synthetic))

                let typeParams = sema.types.nominalTypeParameterSymbols(for: kProperty1Symbol)
                #expect(typeParams.count == 2)
                #expect(sema.types.nominalTypeParameterVariances(for: kProperty1Symbol) == [.invariant, .out])

                let receiverParamType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
                let valueType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[1], nullability: .nonNull)))
                let receiverType = sema.types.make(.classType(ClassType(
                    classSymbol: kProperty1Symbol,
                    args: [.invariant(receiverParamType), .invariant(valueType)],
                    nullability: .nonNull
                )))

                #expect(sema.symbols.directSupertypes(for: kProperty1Symbol).contains(kPropertySymbol))
                #expect(
                    sema.symbols.supertypeTypeArgs(for: kProperty1Symbol, supertype: kPropertySymbol) == [.invariant(valueType)]
                )
                #expect(sema.symbols.directSupertypes(for: kProperty1Symbol).contains(function1Symbol))
                #expect(
                    sema.symbols.supertypeTypeArgs(for: kProperty1Symbol, supertype: function1Symbol) == [.out(valueType), .in(receiverParamType)]
                )

                let getSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KProperty1"), interner.intern("get")]
                ))
                let getSignature = try #require(sema.symbols.functionSignature(for: getSymbol))
                #expect(getSignature.receiverType == receiverType)
                #expect(getSignature.parameterTypes == [receiverParamType])
                #expect(getSignature.returnType == valueType)
                #expect(getSignature.typeParameterSymbols == typeParams)
                #expect(getSignature.classTypeParameterCount == 2)

                let getDelegateSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KProperty1"), interner.intern("getDelegate")]
                ))
                let getDelegateSignature = try #require(sema.symbols.functionSignature(for: getDelegateSymbol))
                #expect(getDelegateSignature.receiverType == receiverType)
                #expect(getDelegateSignature.parameterTypes == [receiverParamType])
                #expect(getDelegateSignature.returnType == sema.types.nullableAnyType)
                #expect(getDelegateSignature.typeParameterSymbols == typeParams)
                #expect(getDelegateSignature.classTypeParameterCount == 2)

                let invokeSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KProperty1"), interner.intern("invoke")]
                ))
                let invokeSignature = try #require(sema.symbols.functionSignature(for: invokeSymbol))
                #expect(invokeSignature.receiverType == receiverType)
                #expect(invokeSignature.parameterTypes == [receiverParamType])
                #expect(invokeSignature.returnType == valueType)
                #expect(sema.symbols.symbol(invokeSymbol)?.flags.contains(.operatorFunction) == true)
                #expect(invokeSignature.typeParameterSymbols == typeParams)
                #expect(invokeSignature.classTypeParameterCount == 2)
            }

            // === testKProperty1MemberCallsResolveInSource ===
            do {
                let path0 = paths[0]
                let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
                #expect(!path0Diagnostics.contains(where: { $0.severity == .error }), "Expected testKProperty1MemberCallsResolveInSource to resolve cleanly, got: \(path0Diagnostics)")
            }
        }
    }

}
#endif
