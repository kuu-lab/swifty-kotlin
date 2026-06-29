#if canImport(Testing)
@testable import CompilerCore
import Testing

// STDLIB-CINTEROP-FN-039: kotlinx.cinterop.typeOf<T>() stub registration
@Suite
struct CinteropTypeOfSyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, "Expected cinterop typeOf surface to resolve cleanly, got: \(diagnostics)")
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testCinteropTypeOfIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let typeOfSymbol = try #require(
            sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("typeOf")]).first,
            "Expected kotlinx.cinterop.typeOf to be registered"
        )
        let info = try #require(sema.symbols.symbol(typeOfSymbol))
        #expect(info.kind == .function)
        #expect(info.flags.contains(.synthetic))
        #expect(info.flags.contains(.inlineFunction))

        let sig = try #require(sema.symbols.functionSignature(for: typeOfSymbol))
        #expect(sig.parameterTypes.isEmpty)
        #expect(sig.reifiedTypeParameterIndices == [0])
        #expect(sig.receiverType == nil)

        let reflectPkg = ["kotlin", "reflect"].map { interner.intern($0) }
        let kTypeSymbol = try #require(
            sema.symbols.lookup(fqName: reflectPkg + [interner.intern("KType")])
        )
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(sig.returnType == expectedReturnType)
    }

    @Test
    func testCinteropTypeOfResolvesInSource() throws {
        let source = """
        import kotlinx.cinterop.typeOf
        import kotlin.reflect.KType

        fun getStringType(): KType = typeOf<String>()
        """
        let (_, _) = try makeSema(source: source)
    }
}
#endif
