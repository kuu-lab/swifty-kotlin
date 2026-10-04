@testable import CompilerCore
import Testing

@Suite
struct CoroutineContextElementKeySourceTests {
    @Test
    func contextIndexInfersElementFromCompanionKey() throws {
        let source = """
        import kotlin.coroutines.*
        import kotlinx.coroutines.*

        @OptIn(ExperimentalCoroutinesApi::class)
        fun lookup(ctx: CoroutineContext) {
            val job: Job? = ctx[Job]
            val explicitJob: Job? = ctx[Job.Key]
            val id: CoroutineId? = ctx[CoroutineId]
            val explicitId: CoroutineId? = ctx[CoroutineId.Key]
        }

        @OptIn(ExperimentalCoroutinesApi::class)
        fun main() = runBlocking {
            val job: Job? = coroutineContext[Job]
            val id: CoroutineId? = coroutineContext[CoroutineId]
            val explicitId: CoroutineId? = coroutineContext[CoroutineId.Key]
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let accesses = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
            guard case let .indexedAccess(_, _, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else { return nil }
            return ExprID(rawValue: Int32(index))
        }
        #expect(accesses.count == 7)
        for access in accesses {
            let binding = try #require(sema.bindings.callBinding(for: access))
            let callee = try #require(sema.symbols.symbol(binding.chosenCallee))
            #expect(callee.fqName.map(ctx.interner.resolve) == ["kotlin", "coroutines", "CoroutineContext", "get"])
            #expect(binding.substitutedTypeArguments.count == 1)
            let element = try #require(binding.substitutedTypeArguments.first)
            #expect(sema.bindings.exprTypes[access] == sema.types.makeNullable(element))
        }
    }

    @Test
    func genericIndexAcceptsNamedCompanionValue() throws {
        let source = """
        interface Token<T>
        class Item {
            companion object Named : Token<Item>
        }
        class Lookup {
            operator fun <T> get(key: Token<T>): T? = null
        }
        fun lookup(value: Lookup): Item? = value[Item]
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: ["key", "get", "fold", "minusKey"])
    func elementMembersHaveOneSourceOwner(name: String) throws {
        let ctx = makeContextFromSource("import kotlin.coroutines.CoroutineContext")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "coroutines", "CoroutineContext", "Element", name].map(ctx.interner.intern)
        let members = sema.symbols.lookupAll(fqName: fqName)
        #expect(members.count == 1)
        let member = try #require(members.first)
        let info = try #require(sema.symbols.symbol(member))
        #expect(info.kind == (name == "key" ? .property : .function))
        #expect(!info.flags.contains(.synthetic))
        #expect(info.declSite != nil)
        #expect(sema.symbols.isSourceBackedSymbol(member))
        #expect(sema.symbols.externalLinkName(for: member) == nil)
        let file = try #require(sema.symbols.sourceFileID(for: member))
        #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/coroutines/CoroutineContext.kt")
    }

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

    @Test
    func wildcardPackageDoesNotReplaceQualifiedSupertypePrefix() throws {
        let imported = """
        package imported.collision
        interface Marker
        """
        let qualified = """
        package collision
        interface Marker
        """
        let source = """
        import imported.collision.*
        class Item : collision.Marker
        fun marker(): collision.Marker = Item()
        """
        let ctx = makeContextFromSources([imported, qualified, source])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let marker = try #require(sema.symbols.lookup(fqName: ["collision", "Marker"].map(ctx.interner.intern)))
        let unrelated = try #require(sema.symbols.lookup(fqName: ["imported", "collision", "Marker"].map(ctx.interner.intern)))
        let item = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Item")]))
        let supertypes = sema.symbols.directSupertypes(for: item)
        #expect(supertypes.contains(marker))
        #expect(!supertypes.contains(unrelated))
    }
}
