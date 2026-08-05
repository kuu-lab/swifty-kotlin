#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeIdentityHashCodeSurfaceTests {
    @Test func testIdentityHashCodeIsRegistered() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.identityHashCode

        fun probe(value: Any?): Int = value.identityHashCode()
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected identityHashCode to resolve without errors, got \(errors)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
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







}
#endif
