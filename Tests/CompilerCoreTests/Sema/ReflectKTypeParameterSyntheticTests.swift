#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKTypeParameterSyntheticTests {

    @Test
    func testReflectKTypeParameterSyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.reflect.KClassifier
            import kotlin.reflect.KType
            import kotlin.reflect.KTypeParameter
            import kotlin.reflect.KVariance

            fun classifierOf(parameter: KTypeParameter): KClassifier = parameter

            fun inspect(parameter: KTypeParameter): KVariance {
                val name: String = parameter.name
                val reified: Boolean = parameter.isReified
                val bounds: List<KType> = parameter.upperBounds
                return parameter.variance
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testKTypeParameterSurfaceIsRegistered ===
            do {

                let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
                let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

                let kClassifierSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KClassifier")]
                ))
                let kTypeSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KType")]
                ))
                let kTypeParameterSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KTypeParameter")]
                ))
                let kVarianceSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KVariance")]
                ))
                let listSymbol = try #require(sema.symbols.lookup(
                    fqName: collectionsPackage + [interner.intern("List")]
                ))

                let kTypeParameterInfo = try #require(sema.symbols.symbol(kTypeParameterSymbol))
                #expect(kTypeParameterInfo.kind == .interface)
                #expect(kTypeParameterInfo.flags.contains(.synthetic))
                #expect(sema.symbols.directSupertypes(for: kTypeParameterSymbol).contains(kClassifierSymbol))

                let kVarianceType = sema.types.make(.classType(ClassType(
                    classSymbol: kVarianceSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let kTypeType = sema.types.make(.classType(ClassType(
                    classSymbol: kTypeSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let listOfKType = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(kTypeType)],
                    nullability: .nonNull
                )))

                let propertyExpectations: [(name: String, type: TypeID)] = [
                    ("name", sema.types.stringType),
                    ("isReified", sema.types.booleanType),
                    ("variance", kVarianceType),
                    ("upperBounds", listOfKType),
                ]
                for expectation in propertyExpectations {
                    let propertySymbol = try #require(sema.symbols.lookup(
                        fqName: reflectPackage + [interner.intern("KTypeParameter"), interner.intern(expectation.name)]
                    ))
                    #expect(sema.symbols.parentSymbol(for: propertySymbol) == kTypeParameterSymbol)
                    #expect(sema.symbols.propertyType(for: propertySymbol) == expectation.type)
                }
            }

            // === testKTypeParameterPropertiesResolveInSource ===
            do {
                let path0 = paths[0]
                let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
                #expect(!path0Diagnostics.contains(where: { $0.severity == .error }), "Expected testKTypeParameterPropertiesResolveInSource to resolve cleanly, got: \(path0Diagnostics)")
            }
        }
    }

}
#endif
