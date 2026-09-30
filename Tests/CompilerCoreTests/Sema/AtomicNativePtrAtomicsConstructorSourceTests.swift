#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct AtomicNativePtrAtomicsConstructorSourceTests {
    @Test
    func constructorAndStorageAreSourceBacked() throws {
        let ctx = makeContextFromSource("""
        @file:OptIn(
            kotlin.concurrent.atomics.ExperimentalAtomicApi::class,
            kotlinx.cinterop.ExperimentalForeignApi::class
        )
        import kotlin.concurrent.atomics.AtomicNativePtr
        import kotlinx.cinterop.NativePtr

        fun construct(value: NativePtr): AtomicNativePtr = AtomicNativePtr(value)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let fqName = ["kotlin", "concurrent", "atomics", "AtomicNativePtr"].map(interner.intern)
        let classSymbol = try #require(sema.symbols.lookup(fqName: fqName))
        let classInfo = try #require(sema.symbols.symbol(classSymbol))
        #expect(classInfo.kind == .class)
        #expect(sema.symbols.isSourceBackedSymbol(classSymbol))

        let constructor = try #require(
            sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")]).first {
                sema.symbols.symbol($0)?.kind == .constructor
            }
        )
        let constructorInfo = try #require(sema.symbols.symbol(constructor))
        #expect(!constructorInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(constructor))
        #expect(sema.symbols.externalLinkName(for: constructor) == nil)
        let fileID = try #require(constructorInfo.declSite?.start.file)
        #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/concurrent/atomics/AtomicNativePtr/Stdlib.kt")

        let field = try #require(sema.symbols.lookup(fqName: fqName + [interner.intern("value")]))
        #expect(sema.symbols.isSourceBackedSymbol(field))
        #expect(sema.symbols.symbol(field)?.flags.contains(.mutable) == true)
    }
}
#endif
