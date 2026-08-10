#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-682: regression coverage for binding supertype type arguments when a
/// generic declaration forwards its own type parameters to a generic supertype
/// (e.g. `interface B<T> : A<T>`) or to a function-type supertype
/// (e.g. `interface C<V> : () -> V`). This capability underpins the bundled
/// Kotlin `KProperty0/1/2` shells.
@Suite
struct GenericInterfaceInheritanceTests {
    @Test
    func testGenericInterfaceInheritanceTestsSourceResolution() throws {
        let sources: [String] = [
            """
            package sample0
            interface A<T> {
                fun g(): T
            }

            interface B<T> : A<T>

            fun useMember(b: B<Int>): Int = b.g()

            fun upcast(b: B<Int>): A<Int> = b
            """,
            """
            package sample1
            interface Producer<V> : () -> V
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for (index, _) in sources.enumerated() {
                let path = paths[index]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                #expect(
                    !pathDiagnostics.contains(where: { $0.severity == .error }),
                    "Expected clean resolution, got: \(pathDiagnostics)"
                )
            }

            // === testGenericInterfaceForwardsTypeParameterToSupertype ===
            do {

                let aSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample0"),
                    interner.intern("A"),
                ]))
                let bSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample0"),
                    interner.intern("B"),
                ]))

                #expect(sema.symbols.directSupertypes(for: bSymbol).contains(aSymbol))

                let bTypeParams = sema.types.nominalTypeParameterSymbols(for: bSymbol)
                #expect(bTypeParams.count == 1)
                let bTypeParam = sema.types.make(.typeParam(TypeParamType(
                    symbol: bTypeParams[0],
                    nullability: .nonNull
                )))
                #expect(
                    sema.symbols.supertypeTypeArgs(for: bSymbol, supertype: aSymbol) == [.invariant(bTypeParam)]
                )
            }

            // === testFunctionTypeSupertypeBindsFunctionInterface ===
            do {

                let producerSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample1"),
                    interner.intern("Producer"),
                ]))
                let function0Symbol = try #require(sema.symbols.lookup(
                    fqName: ["kotlin", "Function", "Function0"].map { interner.intern($0) }
                ))

                #expect(sema.symbols.directSupertypes(for: producerSymbol).contains(function0Symbol))

                let typeParams = sema.types.nominalTypeParameterSymbols(for: producerSymbol)
                #expect(typeParams.count == 1)
                let valueType = sema.types.make(.typeParam(TypeParamType(
                    symbol: typeParams[0],
                    nullability: .nonNull
                )))
                #expect(
                    sema.symbols.supertypeTypeArgs(for: producerSymbol, supertype: function0Symbol) == [.out(valueType)]
                )
            }
        }
    }
}
#endif
