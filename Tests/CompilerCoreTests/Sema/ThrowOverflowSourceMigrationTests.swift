#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-959: the overflow helpers must be bundled Kotlin source declarations,
/// not synthetic or runtime-linked functions, and their block-body return type is Unit.
@Suite
struct ThrowOverflowSourceMigrationTests {
    @Test
    func testThrowOverflowHelpersAreSourceBackedUnitFunctions() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Expected bundled stdlib Sema to succeed")
            let sema = try #require(ctx.sema)
            let package = ["kotlin", "collections"].map { ctx.interner.intern($0) }

            for name in ["throwCountOverflow", "throwIndexOverflow"] {
                let symbol = try #require(
                    sema.symbols.lookup(fqName: package + [ctx.interner.intern(name)]),
                    "Expected kotlin.collections.\(name)"
                )
                let info = try #require(sema.symbols.symbol(symbol))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                let fileID = try #require(sema.symbols.sourceFileID(for: symbol))

                #expect(info.kind == .function)
                #expect(info.visibility == .internal)
                #expect(!info.flags.contains(.synthetic))
                #expect(signature.parameterTypes.isEmpty)
                #expect(signature.returnType == sema.types.unitType)
                #expect(sema.symbols.externalLinkName(for: symbol) == nil)
                #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/throw.kt")
            }
        }
    }
}
#endif
