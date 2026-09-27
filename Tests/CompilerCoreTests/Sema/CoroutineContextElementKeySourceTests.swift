@testable import CompilerCore
import Testing

@Suite
struct CoroutineContextElementKeySourceTests {
    @Test
    func keyIsAnOverridableSourceProperty() throws {
        let source = """
        import kotlin.coroutines.AbstractCoroutineContextElement
        import kotlin.coroutines.CoroutineContext

        class Item : AbstractCoroutineContextElement(Key) {
            companion object Key : CoroutineContext.Key<Item>
            override val key: CoroutineContext.Key<*> get() = Key
        }

        fun key(item: AbstractCoroutineContextElement): CoroutineContext.Key<*> = item.key
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "coroutines", "AbstractCoroutineContextElement", "key"].map(ctx.interner.intern)
        let key = try #require(sema.symbols.lookup(fqName: fqName))
        let info = try #require(sema.symbols.symbol(key))
        #expect(info.kind == .property)
        #expect(!info.flags.contains(.synthetic))
        let file = try #require(sema.symbols.sourceFileID(for: key))
        #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/coroutines/CoroutineContextImpl.kt")
    }

    @Test(arguments: [false, true])
    func importedClassifierCanQualifyNestedSupertype(useAlias: Bool) throws {
        let declaration = """
        package nested
        interface Outer {
            interface Marker
        }
        """
        let qualifier = useAlias ? "Alias" : "Outer"
        let source = """
        import nested.Outer\(useAlias ? " as Alias" : "")
        class Item : \(qualifier).Marker
        fun marker(): \(qualifier).Marker = Item()
        """
        let ctx = makeContextFromSources([declaration, source])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let marker = try #require(sema.symbols.lookup(fqName: ["nested", "Outer", "Marker"].map(ctx.interner.intern)))
        let item = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Item")]))
        #expect(sema.symbols.directSupertypes(for: item).contains(marker))
    }
}
