#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKTypeProjectionSyntheticTests {

    @Test
    func testReflectKTypeProjectionSyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.reflect.KType
            import kotlin.reflect.KTypeProjection
            import kotlin.reflect.KVariance

            fun projectionVariance(projection: KTypeProjection): KVariance? = projection.variance
            fun projectionType(projection: KTypeProjection): KType? = projection.type
            fun typeArguments(type: KType): List<KTypeProjection> = type.arguments
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testKTypeProjectionPropertiesAreRegistered ===
            do {

                let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
                let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

                let kTypeSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KType")]
                ))
                let kTypeProjectionSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KTypeProjection")]
                ))
                let kVarianceSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KVariance")]
                ))
                let listSymbol = try #require(sema.symbols.lookup(
                    fqName: collectionsPackage + [interner.intern("List")]
                ))

                #expect(sema.symbols.symbol(kTypeProjectionSymbol)?.kind == .class)
                #expect(sema.symbols.symbol(kTypeProjectionSymbol)?.flags.contains(.synthetic) == true)

                let nullableKVariance = sema.types.makeNullable(sema.types.make(.classType(ClassType(
                    classSymbol: kVarianceSymbol,
                    args: [],
                    nullability: .nonNull
                ))))
                let nullableKType = sema.types.makeNullable(sema.types.make(.classType(ClassType(
                    classSymbol: kTypeSymbol,
                    args: [],
                    nullability: .nonNull
                ))))

                let varianceSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KTypeProjection"), interner.intern("variance")]
                ))
                let typeSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KTypeProjection"), interner.intern("type")]
                ))
                #expect(sema.symbols.propertyType(for: varianceSymbol) == nullableKVariance)
                #expect(sema.symbols.propertyType(for: typeSymbol) == nullableKType)

                let projectionType = sema.types.make(.classType(ClassType(
                    classSymbol: kTypeProjectionSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let listOfProjection = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(projectionType)],
                    nullability: .nonNull
                )))
                let argumentsSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KType"), interner.intern("arguments")]
                ))
                #expect(sema.symbols.propertyType(for: argumentsSymbol) == listOfProjection)
            }

            // === testKTypeProjectionPropertiesResolveInSource ===
            do {
                let path0 = paths[0]
                let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
                #expect(!path0Diagnostics.contains(where: { $0.severity == .error }), "Expected testKTypeProjectionPropertiesResolveInSource to resolve cleanly, got: \(path0Diagnostics)")
            }
        }
    }

}
#endif
