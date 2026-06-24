#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectCreateInstanceSyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected createInstance surface to resolve cleanly, got: \(diagnostics)"))
            result = try (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testCreateInstanceSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let functionFQName = ["kotlin", "reflect", "full", "createInstance"].map { interner.intern($0) }
        let functionSymbol = try #require(
            sema.symbols.lookupAll(fqName: functionFQName).first,
            "Expected kotlin.reflect.full.createInstance to be registered"
        )
        let symbol = try #require(sema.symbols.symbol(functionSymbol))
        let signature = try #require(sema.symbols.functionSignature(for: functionSymbol))

        #expect(symbol.kind == .function)
        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))
        #expect(signature.parameterTypes == [])
        #expect(signature.typeParameterSymbols.count == 1)
        #expect(signature.typeParameterUpperBoundsList == [[sema.types.anyType]])

        let typeParam = try #require(signature.typeParameterSymbols.first)
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParam,
            nullability: .nonNull
        )))
        let kClassSymbol = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "reflect", "KClass"].map { interner.intern($0) }
        ))
        #expect(signature.receiverType == sema.types.make(.classType(ClassType(
            classSymbol: kClassSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        ))))
        #expect(signature.returnType == typeParamType)
    }

    @Test func testCreateInstanceResolvesInSource() throws {
        let source = """
        import kotlin.reflect.KClass
        import kotlin.reflect.full.createInstance

        class Box

        fun makeBox(): Box = Box::class.createInstance()

        fun <T : Any> make(kclass: KClass<T>): T =
            kclass.createInstance()
        """

        _ = try makeSema(source: source)
    }
}
#endif
