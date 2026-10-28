@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct CoroutineContextElementKeySourceTests {
    @Test(arguments: [false, true])
    func userKeyValueIsChosenAndUnrelatedObjectRejected(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let source = """
        import kotlin.coroutines.CoroutineContext
        object Key : CoroutineContext.Key<Element>
        class Element : CoroutineContext.Element {
            override val key: CoroutineContext.Key<*> = Key
        }
        object Wrong
        class BadElement : CoroutineContext.Element {
            override val key: CoroutineContext.Key<*> = Wrong
        }
        """
        let context = makeContextFromSource(
            source, emit: useLibrary ? .executable : .kirDump,
            allowDefaultStdlibLibrary: useLibrary
        )
        try runSema(context)
        if useLibrary { #expect(context.options.stdlibLibraryPath != nil) }
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.first?.code == "KSWIFTK-TYPE-0001")
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        let keyObject = try #require(sema.symbols.lookup(fqName: [context.interner.intern("Key")]))
        let boundKeyReferences = ast.arena.exprs.enumerated().compactMap { index, expression -> SymbolID? in
            guard case let .nameRef(name, range) = expression,
                  context.interner.resolve(name) == "Key",
                  context.sourceManager.origin(of: range.start.file) == .user else { return nil }
            return sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(index)))
        }
        #expect(boundKeyReferences.contains(keyObject))
    }

    @Test
    func baseContextBridgeSlotsAndSignatures() throws {
        let ctx = makeContextFromSource("""
        import kotlin.coroutines.CoroutineContext
        object Key : CoroutineContext.Key<Element>
        class Element : CoroutineContext.Element {
            override val key: CoroutineContext.Key<*> = Key
        }
        fun lookup(context: CoroutineContext) {
            val indexed: Element? = context[Key]
            val explicit: Element? = context.get(Key)
            val removed: CoroutineContext = context.minusKey(Key)
            val combined: CoroutineContext = context.plus(Element())
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let context = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "coroutines", "CoroutineContext"].map(ctx.interner.intern)
        ))
        let layout = try #require(sema.symbols.nominalLayout(for: context))
        let members: [(String, Int, SemaRuntimeFunction)] = [
            ("get", 0, .contextGetDispatch), ("plus", 2, .contextPlusDispatch), ("minusKey", 3, .contextMinusKeyDispatch),
        ]
        for (name, slot, bridge) in members {
            let member = try #require(sema.symbols.lookup(
                fqName: ["kotlin", "coroutines", "CoroutineContext", name].map(ctx.interner.intern)
            ))
            #expect(layout.vtableSlots[member] == slot)
            #expect(sema.symbols.externalLinkName(for: member) == runtimeABIName(bridge))
            #expect(sema.symbols.functionSignature(for: member)?.receiverType != nil)
        }
    }

    @Test(arguments: [false, true])
    func contextIndexInfersElementFromCompanionKey(useLibrary: Bool) throws {
        let source = """
        import kotlin.coroutines.*
        import kotlinx.coroutines.*

        @OptIn(ExperimentalCoroutinesApi::class)
        fun lookup(ctx: CoroutineContext) {
            val job: Job? = ctx[Job]
            val explicitJob: Job? = ctx[Job.Key]
            val id: CoroutineId? = ctx[CoroutineId]
            val explicitId: CoroutineId? = ctx[CoroutineId.Key]
            val interceptor: ContinuationInterceptor? = ctx[ContinuationInterceptor]
        }

        fun composed(job: Job) {
            val ctx = EmptyCoroutineContext + job
            val found: Job? = ctx[Job]
        }

        fun concreteEmptyContext() {
            val job: Job? = EmptyCoroutineContext[Job]
            val interceptor: ContinuationInterceptor? = EmptyCoroutineContext[ContinuationInterceptor]
        }

        @OptIn(ExperimentalCoroutinesApi::class)
        fun main() = runBlocking {
            val job: Job? = coroutineContext[Job]
            val id: CoroutineId? = coroutineContext[CoroutineId]
            val explicitId: CoroutineId? = coroutineContext[CoroutineId.Key]
        }
        """
        let ctx = makeContextFromSource(source, allowDefaultStdlibLibrary: useLibrary)
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
        #expect(accesses.count == 11)
        var concreteEmptyAccesses = 0
        for access in accesses {
            let binding = try #require(sema.bindings.callBinding(for: access))
            let callee = try #require(sema.symbols.symbol(binding.chosenCallee))
            let calleeFQName = callee.fqName.map(ctx.interner.resolve)
            if calleeFQName == ["kotlin", "coroutines", "EmptyCoroutineContext", "get"] {
                concreteEmptyAccesses += 1
            } else {
                #expect(calleeFQName == ["kotlin", "coroutines", "CoroutineContext", "get"])
            }
            #expect(binding.substitutedTypeArguments.count == 1)
            let element = try #require(binding.substitutedTypeArguments.first)
            #expect(sema.bindings.exprTypes[access] == sema.types.makeNullable(element))
        }
        #expect(concreteEmptyAccesses == 2)
    }

    @Test(arguments: ["", "Named"])
    func genericIndexAcceptsCompanionValue(companionName: String) throws {
        let source = """
        interface Token<T>
        class Item {
            companion object \(companionName) : Token<Item>
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

    @Test
    func genericIndexRejectsCompanionWithoutKeySupertype() throws {
        let source = """
        interface Token<T>
        class Item {
            companion object Named
        }
        class Lookup {
            operator fun <T> get(key: Token<T>): T? = null
        }
        fun lookup(value: Lookup): Item? = value[Item]
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    struct ElementMemberExpectation: Sendable {
        let name: String
        let expectedKind: SymbolKind
    }

    @Test(arguments: [
        ElementMemberExpectation(name: "key", expectedKind: .property),
        ElementMemberExpectation(name: "get", expectedKind: .function),
        ElementMemberExpectation(name: "fold", expectedKind: .function),
        ElementMemberExpectation(name: "minusKey", expectedKind: .function),
    ])
    func elementMembersHaveOneSourceOwner(expectation: ElementMemberExpectation) throws {
        let ctx = makeContextFromSource("import kotlin.coroutines.CoroutineContext")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "coroutines", "CoroutineContext", "Element", expectation.name].map(ctx.interner.intern)
        let members = sema.symbols.lookupAll(fqName: fqName)
        #expect(members.count == 1)
        let member = try #require(members.first)
        let info = try #require(sema.symbols.symbol(member))
        #expect(info.kind == expectation.expectedKind)
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

    struct NestedClassifierImportCase: Sendable {
        let qualifier: String
        let importClause: String
    }

    @Test(arguments: [
        NestedClassifierImportCase(qualifier: "Outer", importClause: "import nested.Outer"),
        NestedClassifierImportCase(qualifier: "Alias", importClause: "import nested.Outer as Alias"),
    ])
    func importedClassifierCanQualifyNestedSupertype(testCase: NestedClassifierImportCase) throws {
        let declaration = """
        package nested
        interface Outer {
            interface Marker
        }
        """
        let source = """
        \(testCase.importClause)
        class Item : \(testCase.qualifier).Marker
        fun marker(): \(testCase.qualifier).Marker = Item()
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
