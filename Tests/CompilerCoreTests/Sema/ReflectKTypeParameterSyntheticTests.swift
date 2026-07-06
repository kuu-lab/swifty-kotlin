#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKTypeParameterSyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected KTypeParameter surface to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKTypeParameterSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testKTypeParameterPropertiesResolveInSource() throws {
        let source = """
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
        """

        _ = try makeSema(source: source)
    }
}
#endif
