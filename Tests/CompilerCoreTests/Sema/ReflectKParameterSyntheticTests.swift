#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKParameterSyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected KParameter surface to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKParameterSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
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
            ("index", sema.types.intType, "kk_kparameter_get_index"),
            ("name", nullableStringType, "kk_kparameter_get_name"),
            ("type", kTypeType, "kk_kparameter_get_type"),
            ("isOptional", sema.types.booleanType, "kk_kparameter_is_optional"),
            ("kind", sema.types.intType, "kk_kparameter_get_kind"),
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

    @Test func testKParameterPropertiesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KParameter
        import kotlin.reflect.KType

        fun inspect(parameter: KParameter): KType {
            val index: Int = parameter.index
            val name: String? = parameter.name
            val optional: Boolean = parameter.isOptional
            val kind: Int = parameter.kind
            return parameter.type
        }
        """

        _ = try makeSema(source: source)
    }
}
#endif
