#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKParameterSyntheticTests {
    private static let fixture = SemaFixture(surface: "KParameter")

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        try Self.fixture.shared()
    }

    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        try Self.fixture.make(source: source)
    }

    @Test func testKParameterSurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()
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
