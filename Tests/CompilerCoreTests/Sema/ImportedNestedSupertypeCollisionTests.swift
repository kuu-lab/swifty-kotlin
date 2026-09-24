#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ImportedNestedSupertypeCollisionTests {
    @Test
    func rootDeclarationsDoNotShadowBundledCoroutineImports() throws {
        let ctx = makeContextFromSource("""
        class Key(val id: Int) {}
        class Element {}
        """)
        try runSema(ctx)

        #expect(
            ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty,
            "Root declarations must not shadow imported coroutine types in bundled source: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let key = try #require(
            sema.symbols.lookupAll(fqName: ["kotlin", "coroutines", "CoroutineContext", "Key"].map(interner.intern))
                .first(where: { sema.symbols.symbol($0)?.kind == .interface })
        )
        let element = try #require(
            sema.symbols.lookupAll(fqName: ["kotlin", "coroutines", "CoroutineContext", "Element"].map(interner.intern))
                .first(where: { sema.symbols.symbol($0)?.kind == .interface })
        )
        let abstractKey = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "AbstractCoroutineContextKey"].map(interner.intern))
        )
        let abstractElement = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "AbstractCoroutineContextElement"].map(interner.intern))
        )

        #expect(sema.symbols.directSupertypes(for: abstractKey).contains(key))
        #expect(sema.symbols.directSupertypes(for: abstractElement).contains(element))
    }
}
#endif
