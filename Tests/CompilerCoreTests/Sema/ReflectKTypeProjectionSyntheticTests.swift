#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKTypeProjectionSyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected KTypeProjection surface to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKTypeProjectionPropertiesAreRegistered() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testKTypeProjectionPropertiesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KType
        import kotlin.reflect.KTypeProjection
        import kotlin.reflect.KVariance

        fun projectionVariance(projection: KTypeProjection): KVariance? = projection.variance
        fun projectionType(projection: KTypeProjection): KType? = projection.type
        fun typeArguments(type: KType): List<KTypeProjection> = type.arguments
        """

        _ = try makeSema(source: source)
    }
}
#endif
