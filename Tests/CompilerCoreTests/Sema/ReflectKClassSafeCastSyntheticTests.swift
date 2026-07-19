#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKClassSafeCastSyntheticTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "Expected KClass.safeCast source to type-check, got: \(ctx.diagnostics.diagnostics)")
            )
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKClassSafeCastInfersNullableReceiverArgumentReturnTypes() throws {
        let source = """
        import kotlin.reflect.KClass

        fun safeCastString(value: Any?): String? = String::class.safeCast(value)

        fun safeCastViaLocal(value: Any?): String? {
            val klass = String::class
            return klass.safeCast(value)
        }

        fun <T : Any> safeCastWithClass(klass: KClass<T>, value: Any?): T? = klass.safeCast(value)
        """
        let (sema, interner) = try makeSema(source: source)
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)

        for functionName in ["safeCastString", "safeCastViaLocal"] {
            let symbol = try #require(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(
                signature.returnType == nullableStringType,
                Comment(rawValue: "\(functionName) should infer String? from KClass<String>.safeCast")
            )
        }

        let genericSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("safeCastWithClass")]))
        let genericSignature = try #require(sema.symbols.functionSignature(for: genericSymbol))
        if case let .typeParam(typeParam) = sema.types.kind(of: genericSignature.returnType) {
            #expect(typeParam.nullability == .nullable)
        } else {
            Issue.record("Expected generic KClass.safeCast wrapper to return nullable T")
        }
    }
}
#endif
