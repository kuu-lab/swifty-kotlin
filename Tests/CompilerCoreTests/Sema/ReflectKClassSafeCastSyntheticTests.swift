#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKClassSafeCastSyntheticTests {
    @Test func testKClassSafeCastInfersNullableReceiverArgumentReturnTypes() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.reflect.KClass

            fun safeCastString(value: Any?): String? = String::class.safeCast(value)

            fun safeCastViaLocal(value: Any?): String? {
                val klass = String::class
                return klass.safeCast(value)
            }

            fun <T : Any> safeCastWithClass(klass: KClass<T>, value: Any?): T? = klass.safeCast(value)
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let path0 = paths[0]
            let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
            #expect(
                !path0Diagnostics.contains(where: { $0.severity == .error }),
                "Expected KClass.safeCast source to type-check, got: \(path0Diagnostics)"
            )

            let nullableStringType = sema.types.makeNullable(sema.types.stringType)
            for functionName in ["safeCastString", "safeCastViaLocal"] {
                let symbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample0"),
                    interner.intern(functionName),
                ]))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(
                    signature.returnType == nullableStringType,
                    "\(functionName) should infer String? from KClass<String>.safeCast"
                )
            }

            let genericSymbol = try #require(sema.symbols.lookup(fqName: [
                interner.intern("sample0"),
                interner.intern("safeCastWithClass"),
            ]))
            let genericSignature = try #require(sema.symbols.functionSignature(for: genericSymbol))
            if case let .typeParam(typeParam) = sema.types.kind(of: genericSignature.returnType) {
                #expect(typeParam.nullability == .nullable)
            } else {
                Issue.record("Expected generic KClass.safeCast wrapper to return nullable T")
            }
        }
    }
}
#endif
