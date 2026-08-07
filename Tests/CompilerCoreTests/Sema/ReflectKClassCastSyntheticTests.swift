#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKClassCastSyntheticTests {
    @Test func testKClassCastInfersReceiverArgumentReturnTypes() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.reflect.KClass

            fun castString(value: Any?): String = String::class.cast(value)

            fun castViaLocal(value: Any?): String {
                val klass = String::class
                return klass.cast(value)
            }

            fun <T : Any> castWithClass(klass: KClass<T>, value: Any?): T = klass.cast(value)
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
                "Expected KClass.cast source to type-check, got: \(path0Diagnostics)"
            )

            for functionName in ["castString", "castViaLocal"] {
                let symbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample0"),
                    interner.intern(functionName),
                ]))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(
                    signature.returnType == sema.types.stringType,
                    "\(functionName) should infer String from KClass<String>.cast"
                )
            }

            let genericSymbol = try #require(sema.symbols.lookup(fqName: [
                interner.intern("sample0"),
                interner.intern("castWithClass"),
            ]))
            let genericSignature = try #require(sema.symbols.functionSignature(for: genericSymbol))
            if case .typeParam = sema.types.kind(of: genericSignature.returnType) {
                // Expected: generic KClass<T>.cast preserves T.
            } else {
                Issue.record("Expected generic KClass.cast wrapper to return T")
            }
        }
    }
}
#endif
