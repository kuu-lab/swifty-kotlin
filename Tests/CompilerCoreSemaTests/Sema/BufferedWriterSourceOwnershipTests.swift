@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct BufferedWriterSourceOwnershipTests {
    @Test(arguments: [false, true])
    func sourceAndImportedWriterKeepTheirPublicSourceOwner(libraryMode: Bool) throws {
        if libraryMode { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource("""
        import kotlin.io.bufferedWriter
        fun writer(out: java.io.OutputStream) = out.bufferedWriter()
        """, emit: libraryMode ? .executable : .kirDump,
        allowDefaultStdlibLibrary: libraryMode)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0102" })
        let sema = try #require(ctx.sema)
        let functions = sema.symbols.lookupAll(fqName: ["kotlin", "io", "bufferedWriter"].map(ctx.interner.intern))
            .filter { sema.symbols.symbol($0)?.kind == .function }
        #expect(functions.count == 1)
        let owner = try #require(functions.first)
        if libraryMode {
            #expect(sema.symbols.symbol(owner)?.flags.contains(.importedLibrary) == true)
        } else {
            #expect(sema.symbols.symbol(owner)?.flags.contains(.synthetic) == false)
            #expect(sema.symbols.isSourceBackedSymbol(owner))
        }
    }
}
