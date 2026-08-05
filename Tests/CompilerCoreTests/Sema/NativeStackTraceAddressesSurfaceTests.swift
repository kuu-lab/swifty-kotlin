#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeStackTraceAddressesSurfaceTests {
    @Test func testGetStackTraceAddressesIsRegistered() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.getStackTraceAddresses

        fun probe(): List<Long> = getStackTraceAddresses()
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected getStackTraceAddresses to resolve without errors, got \(errors)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let nativeFQName = ["kotlin", "native", "getStackTraceAddresses"].map { interner.intern($0) }
        let listFQName = ["kotlin", "collections", "List"].map { interner.intern($0) }
        let listSymbol = try #require(sema.symbols.lookup(fqName: listFQName))
        let listLongType = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(sema.types.longType)],
            nullability: .nonNull
        )))
        let candidates = sema.symbols.lookupAll(fqName: nativeFQName)
        let match = candidates.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.isEmpty
                && signature.returnType == listLongType
        }
        let symbol = try #require(match, "Expected kotlin.native.getStackTraceAddresses")
        #expect(sema.symbols.externalLinkName(for: symbol) == "kk_native_getStackTraceAddresses")
        #expect(
            sema.symbols.annotations(for: symbol).contains {
                $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
            },
            "getStackTraceAddresses must carry ExperimentalNativeApi metadata"
        )
    }







}
#endif
