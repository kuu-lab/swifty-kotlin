#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKVarianceSyntheticTests {

    @Test
    func testReflectKVarianceSyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.reflect.KVariance

            fun invariantVariance(): KVariance = KVariance.INVARIANT
            fun inVariance(): KVariance = KVariance.IN
            fun outVariance(): KVariance = KVariance.OUT
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testKVarianceEnumEntriesAreRegistered ===
            do {

                let enumFQName = ["kotlin", "reflect", "KVariance"].map { interner.intern($0) }
                let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))
                #expect(sema.symbols.symbol(enumSymbol)?.kind == .enumClass)
                #expect(sema.symbols.symbol(enumSymbol)?.flags.contains(.synthetic) == true)

                let enumType = sema.types.make(.classType(ClassType(
                    classSymbol: enumSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                for entry in ["INVARIANT", "IN", "OUT"] {
                    let entrySymbol = try #require(sema.symbols.lookup(fqName: enumFQName + [interner.intern(entry)]))
                    #expect(sema.symbols.symbol(entrySymbol)?.kind == .field)
                    #expect(sema.symbols.parentSymbol(for: entrySymbol) == enumSymbol)
                    #expect(sema.symbols.propertyType(for: entrySymbol) == enumType)
                }
            }

            // === testKVarianceEntriesResolveInSource ===
            do {
                let path0 = paths[0]
                let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
                #expect(!path0Diagnostics.contains(where: { $0.severity == .error }), "Expected testKVarianceEntriesResolveInSource to resolve cleanly, got: \(path0Diagnostics)")
            }
        }
    }

}
#endif
