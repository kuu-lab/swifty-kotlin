#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropByteArrayToKStringFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun noop() {}
        """,
        """
        package sample1
        import kotlinx.cinterop.toKString

        fun decode(bytes: ByteArray): String {
            return bytes.toKString()
        }
        """,
        """
        package sample2
        import kotlinx.cinterop.toKString

        fun decode(bytes: ByteArray): String {
            return bytes.toKString(0, bytes.size, false)
        }
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    @Test func testByteArrayToKStringFunctionSurfaceMatchesNativeShape() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "compile clean: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let byteArraySymbol = try #require(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("ByteArray")]),
            "kotlin.ByteArray must be registered"
        )
        let byteArrayType = sema.types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))

        let candidates = sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKString")])
        let fn = try #require(candidates.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == byteArrayType
                && sig.parameterTypes == [sema.types.intType, sema.types.intType, sema.types.booleanType]
                && sig.returnType == sema.types.stringType
        }, "ByteArray.toKString(startIndex, endIndex, throwOnInvalidSequence) must be registered")
        let flags = try #require(sema.symbols.symbol(fn)?.flags)
        #expect(!flags.contains(.synthetic))

        // Verify all three parameters have default values
        let sig = try #require(sema.symbols.functionSignature(for: fn))
        #expect(sig.valueParameterHasDefaultValues == [true, true, true])
    }

    @Test func testByteArrayToKStringFunctionResolvesInSource() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "resolve with no args: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testByteArrayToKStringFunctionResolvesWithAllArgs() throws {

        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "resolve with all args: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
