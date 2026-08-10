#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKProperty0SyntheticTests {

    @Test
    func testReflectKProperty0SyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.reflect.KProperty0

            fun <V> read(property: KProperty0<V>): V {
                val first = property.get()
                val second = property.invoke()
                return first
            }

            fun <V> delegateOf(property: KProperty0<V>): Any? =
                property.getDelegate()
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testKProperty0SurfaceIsRegistered ===
            do {

                let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
                let functionPackage = ["kotlin", "Function"].map { interner.intern($0) }

                let kPropertySymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KProperty")]
                ))
                let kProperty0Symbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KProperty0")]
                ))
                let function0Symbol = try #require(sema.symbols.lookup(
                    fqName: functionPackage + [interner.intern("Function0")]
                ))

                let kProperty0Info = try #require(sema.symbols.symbol(kProperty0Symbol))
                #expect(kProperty0Info.kind == .interface)
                // KSP-682: KProperty0 is now bundled Kotlin source, not a synthetic stub.
                #expect(!kProperty0Info.flags.contains(.synthetic))

                let typeParams = sema.types.nominalTypeParameterSymbols(for: kProperty0Symbol)
                #expect(typeParams.count == 1)
                #expect(sema.types.nominalTypeParameterVariances(for: kProperty0Symbol) == [.out])

                let valueType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
                let receiverType = sema.types.make(.classType(ClassType(
                    classSymbol: kProperty0Symbol,
                    args: [.invariant(valueType)],
                    nullability: .nonNull
                )))

                #expect(sema.symbols.directSupertypes(for: kProperty0Symbol).contains(kPropertySymbol))
                #expect(
                    sema.symbols.supertypeTypeArgs(for: kProperty0Symbol, supertype: kPropertySymbol) == [.invariant(valueType)]
                )
                #expect(sema.symbols.directSupertypes(for: kProperty0Symbol).contains(function0Symbol))
                #expect(
                    sema.symbols.supertypeTypeArgs(for: kProperty0Symbol, supertype: function0Symbol) == [.out(valueType)]
                )

                let getSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KProperty0"), interner.intern("get")]
                ))
                let getSignature = try #require(sema.symbols.functionSignature(for: getSymbol))
                #expect(getSignature.receiverType == receiverType)
                #expect(getSignature.parameterTypes == [])
                #expect(getSignature.returnType == valueType)
                #expect(getSignature.typeParameterSymbols == typeParams)
                #expect(getSignature.classTypeParameterCount == 1)

                let getDelegateSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KProperty0"), interner.intern("getDelegate")]
                ))
                let getDelegateSignature = try #require(sema.symbols.functionSignature(for: getDelegateSymbol))
                #expect(getDelegateSignature.receiverType == receiverType)
                #expect(getDelegateSignature.parameterTypes == [])
                #expect(getDelegateSignature.returnType == sema.types.nullableAnyType)
                #expect(getDelegateSignature.typeParameterSymbols == typeParams)
                #expect(getDelegateSignature.classTypeParameterCount == 1)

                let invokeSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KProperty0"), interner.intern("invoke")]
                ))
                let invokeSignature = try #require(sema.symbols.functionSignature(for: invokeSymbol))
                #expect(invokeSignature.receiverType == receiverType)
                #expect(invokeSignature.parameterTypes == [])
                #expect(invokeSignature.returnType == valueType)
                #expect(sema.symbols.symbol(invokeSymbol)?.flags.contains(.operatorFunction) == true)
                #expect(invokeSignature.typeParameterSymbols == typeParams)
                #expect(invokeSignature.classTypeParameterCount == 1)
            }

            // === testKProperty0MemberCallsResolveInSource ===
            do {
                let path0 = paths[0]
                let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
                #expect(!path0Diagnostics.contains(where: { $0.severity == .error }), "Expected testKProperty0MemberCallsResolveInSource to resolve cleanly, got: \(path0Diagnostics)")
            }
        }
    }

}
#endif
