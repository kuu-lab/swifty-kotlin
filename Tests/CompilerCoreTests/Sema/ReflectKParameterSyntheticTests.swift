#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKParameterSyntheticTests {

    @Test
    func testReflectKParameterSyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.reflect.KParameter
            import kotlin.reflect.KType

            fun inspect(parameter: KParameter): KType {
                val index: Int = parameter.index
                val name: String? = parameter.name
                val optional: Boolean = parameter.isOptional
                val kind: Int = parameter.kind
                return parameter.type
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testKParameterSurfaceIsRegistered ===
            do {

                let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }

                let kTypeSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KType")]
                ))
                let kParameterSymbol = try #require(sema.symbols.lookup(
                    fqName: reflectPackage + [interner.intern("KParameter")]
                ))

                let kParameterInfo = try #require(sema.symbols.symbol(kParameterSymbol))
                #expect(kParameterInfo.kind == .interface)
                #expect(kParameterInfo.flags.contains(.synthetic))

                let kTypeType = sema.types.make(.classType(ClassType(
                    classSymbol: kTypeSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let nullableStringType = sema.types.makeNullable(sema.types.stringType)
                let propertyExpectations: [(name: String, type: TypeID, externalLinkName: String)] = [
                    ("index", sema.types.intType, "__kk_kparameter_get_index"),
                    ("name", nullableStringType, "__kk_kparameter_get_name"),
                    ("type", kTypeType, "__kk_kparameter_get_type"),
                    ("isOptional", sema.types.booleanType, "__kk_kparameter_is_optional"),
                    ("kind", sema.types.intType, "__kk_kparameter_get_kind"),
                ]

                for expectation in propertyExpectations {
                    let propertySymbol = try #require(sema.symbols.lookup(
                        fqName: reflectPackage + [interner.intern("KParameter"), interner.intern(expectation.name)]
                    ))
                    #expect(sema.symbols.parentSymbol(for: propertySymbol) == kParameterSymbol)
                    #expect(sema.symbols.propertyType(for: propertySymbol) == expectation.type)
                    #expect(sema.symbols.externalLinkName(for: propertySymbol) == expectation.externalLinkName)
                }
            }

            // === testKParameterPropertiesResolveInSource ===
            do {
                let path0 = paths[0]
                let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
                #expect(!path0Diagnostics.contains(where: { $0.severity == .error }), "Expected testKParameterPropertiesResolveInSource to resolve cleanly, got: \(path0Diagnostics)")
            }
        }
    }

}
#endif
