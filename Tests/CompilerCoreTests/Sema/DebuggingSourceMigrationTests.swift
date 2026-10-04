#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1259: kotlin.native.runtime.Debugging is a bundled source object.
@Suite
struct DebuggingSourceMigrationTests {
    @Test
    func debuggingIsSourceBackedObject() throws {
        let ctx = makeContextFromSource(
            """
            @file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

            import kotlin.native.runtime.Debugging

            fun debuggingSingleton(): Debugging = Debugging
            """
        )
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected Debugging to type-check, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let debuggingFQName = ["kotlin", "native", "runtime", "Debugging"].map(ctx.interner.intern)
        let debuggingSymbol = try #require(sema.symbols.lookup(fqName: debuggingFQName))

        #expect(sema.symbols.symbol(debuggingSymbol)?.kind == .object)
        #expect(sema.symbols.isSourceBackedSymbol(debuggingSymbol))
        #expect(sema.symbols.symbol(debuggingSymbol)?.flags.contains(.synthetic) == false)

        let sourceFileID = try #require(sema.symbols.sourceFileID(for: debuggingSymbol))
        #expect(
            ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/native/runtime/Debugging.kt"
        )
    }
}
#endif
