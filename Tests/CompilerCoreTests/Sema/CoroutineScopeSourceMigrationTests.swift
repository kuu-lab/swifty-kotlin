#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CoroutineScopeSourceMigrationTests {
    @Test
    func factoriesAndHelpersUseBundledDeclarations() throws {
        let ctx = makeContextFromSource("""
        import kotlin.coroutines.EmptyCoroutineContext
        import kotlinx.coroutines.*

        suspend fun probe() {
            val job: CompletableJob = Job()
            SupervisorJob(job)
            job.complete()
            val scope = CoroutineScope(EmptyCoroutineContext)
            scope.ensureActive()
            scope.cancel()
            scope.coroutineContext.ensureActive()
            scope.coroutineContext.cancel()
            currentCoroutineContext()
            MainScope().cancel()
            println(GlobalScope.isActive)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let package = ["kotlinx", "coroutines"].map(ctx.interner.intern)
        #expect(sema.symbols.lookupAll(fqName: ["kotlin", "coroutines", "CoroutineContext", "cancel"].map(ctx.interner.intern)).isEmpty)

        for name in ["Job", "SupervisorJob", "CoroutineScope", "MainScope", "currentCoroutineContext"] {
            let symbol = try #require(sema.symbols.lookupAll(fqName: package + [ctx.interner.intern(name)]).first {
                sema.symbols.symbol($0)?.kind == .function
            })
            #expect(sema.symbols.isSourceBackedSymbol(symbol), "\(name) should be source backed")
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)
        }

        let activeProperties = sema.symbols.lookupAll(fqName: package + [ctx.interner.intern("isActive")]).filter {
            sema.symbols.extensionPropertyReceiverType(for: $0) != nil
        }
        #expect(activeProperties.count == 2)
        #expect(Set(activeProperties.compactMap { sema.symbols.extensionPropertyReceiverType(for: $0) }).count == 2)
        for property in activeProperties {
            #expect(sema.symbols.isSourceBackedSymbol(property))
            #expect(sema.symbols.extensionPropertyGetterAccessor(for: property) != nil)
            #expect(sema.symbols.externalLinkName(for: property) == nil)
        }
    }

    @Test
    func extensionPropertiesWithDifferentReceiversKeepSeparateSymbols() throws {
        let ctx = makeContextFromSource("""
        package sample
        class First
        class Second
        val First.active: Boolean get() = true
        val Second.active: Boolean get() = false
        fun probe(first: First, second: Second) {
            println(first.active)
            println(second.active)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let properties = sema.symbols.lookupAll(fqName: ["sample", "active"].map(ctx.interner.intern))
        #expect(properties.count == 2)
        #expect(Set(properties.compactMap { sema.symbols.extensionPropertyReceiverType(for: $0) }).count == 2)
    }
}
#endif
