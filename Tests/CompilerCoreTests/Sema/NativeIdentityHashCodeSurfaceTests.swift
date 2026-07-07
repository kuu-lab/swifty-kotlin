#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeIdentityHashCodeSurfaceTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx
    }

    @Test
    func testIdentityHashCodeIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let nativeFQName = ["kotlin", "native", "identityHashCode"].map { interner.intern($0) }
        let receiverType = sema.types.makeNullable(sema.types.anyType)
        let candidates = sema.symbols.lookupAll(fqName: nativeFQName)
        let match = candidates.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.intType
        }
        let symbol = try #require(match, "Expected kotlin.native.identityHashCode Any? extension")

        #expect(sema.symbols.externalLinkName(for: symbol) == "kk_native_identityHashCode")
        #expect(
            sema.symbols.annotations(for: symbol).contains {
                $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
            },
            "identityHashCode must carry ExperimentalNativeApi metadata"
        )
    }

    @Test
    func testIdentityHashCodeResolvesInSourceWithOptIn() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.identityHashCode

        fun probe(value: Any?): Int = value.identityHashCode()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(errors.isEmpty, "Expected identityHashCode to resolve without errors, got \(errors)")
    }
}
#endif
