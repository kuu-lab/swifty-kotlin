@testable import CompilerCore
import Testing

@Suite
struct CoroutineNameSourceTests {
    @Test
    func indexedArgumentsUseCompanionTypesForUserDefinedKeys() throws {
        let ctx = makeContextFromSource("""
        interface Key<E>
        class Item {
            companion object : Key<Item>
        }
        class Table {
            operator fun <E> get(key: Key<E>): E? = null
        }
        fun lookup(table: Table): Item? = table[Item]
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nameElementAndCompanionKeyResolveFromBundledSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.coroutines.CoroutineContext
        import kotlinx.coroutines.CoroutineName

        fun lookup(ctx: CoroutineContext): CoroutineName? = ctx[CoroutineName]
        fun explicit(ctx: CoroutineContext): CoroutineName? = ctx[CoroutineName.Key]
        fun get(ctx: CoroutineContext): CoroutineName? = ctx.get(CoroutineName)
        fun element(name: CoroutineName): CoroutineContext.Element = name
        fun key(): CoroutineContext.Key<CoroutineName> = CoroutineName
        fun name(element: CoroutineName): String = element.name
        fun elementKey(element: CoroutineName): CoroutineContext.Key<*> = element.key
        fun create(): CoroutineName = CoroutineName(name = "worker")
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let fqName = ["kotlinx", "coroutines", "CoroutineName"].map(ctx.interner.intern)
        let nominals = sema.symbols.lookupAll(fqName: fqName).filter {
            sema.symbols.symbol($0)?.kind == .class
        }
        #expect(nominals.count == 1)
        let nameSymbol = try #require(nominals.first)
        #expect(sema.symbols.isSourceBackedSymbol(nameSymbol))
        let elementSymbol = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "coroutines", "CoroutineContext", "Element"].map(ctx.interner.intern)
        ))
        #expect(sema.symbols.directSupertypes(for: nameSymbol).contains(elementSymbol))
        #expect(sema.symbols.nominalLayout(for: elementSymbol)?.vtableSize == 3)
        let companion = try #require(sema.symbols.companionObjectSymbol(for: nameSymbol))
        #expect(sema.symbols.symbol(companion)?.name == ctx.interner.intern("Key"))
        #expect(sema.symbols.isSourceBackedSymbol(companion))
        #expect(sema.symbols.externalLinkName(for: companion) == "kk_coroutine_name_key")
        let records = MetadataEncoder().buildRecords(
            symbols: sema.symbols,
            types: sema.types,
            moduleName: "KSwiftKStdlib",
            interner: ctx.interner,
            functionLinkNames: [:]
        )
        let keyRecord = try #require(records.first {
            $0.fqName == "kotlinx.coroutines.CoroutineName.Key"
        })
        #expect(keyRecord.externalLinkName == "kk_coroutine_name_key")
        for encoded in [MetadataEncoder().serialize(records), MetadataEncoder().serializeIndexed(records)] {
            let decoded = MetadataDecoder().decode(encoded)
            #expect(decoded.first { $0.fqName == keyRecord.fqName }?.externalLinkName == "kk_coroutine_name_key")
            #expect(decoded.first { $0.fqName == "kotlinx.coroutines.CoroutineName.name" }?.externalLinkName == "kk_coroutine_name_get")
        }
        for (member, link) in [("name", "kk_coroutine_name_get"), ("key", "kk_coroutine_name_key_get")] {
            let property = try #require(sema.symbols.lookup(fqName: fqName + [ctx.interner.intern(member)]))
            #expect(sema.symbols.isSourceBackedSymbol(property))
            #expect(sema.symbols.externalLinkName(for: property) == link)
            let propertyRecord = MetadataEncoder().buildRecord(
                for: try #require(sema.symbols.symbol(property)),
                symbols: sema.symbols,
                types: sema.types,
                moduleName: "KSwiftKStdlib",
                interner: ctx.interner,
                functionLinkNames: [SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: property): "get"]
            )
            #expect(propertyRecord.externalLinkName == link)
            #expect(propertyRecord.propertyGetterExternalLinkName == link)
        }
    }
}
