@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CoroutineExceptionHandlerSourceTests {
    @Test
    func nominalIsInterfaceSupportingDelegationFactoryAndLookup() throws {
        let ctx = makeContextFromSource("""
        import kotlin.coroutines.AbstractCoroutineContextElement
        import kotlin.coroutines.CoroutineContext
        import kotlinx.coroutines.CoroutineExceptionHandler
        import kotlin.coroutines.EmptyCoroutineContext

        class Collector : AbstractCoroutineContextElement(CoroutineExceptionHandler.Key), CoroutineExceptionHandler {
            override fun handleException(context: CoroutineContext, exception: Throwable) {}
        }

        class Delegating(inner: CoroutineExceptionHandler) : CoroutineExceptionHandler by inner

        fun probe() {
            val collector = Collector()
            val delegating = Delegating(collector)
            delegating.handleException(EmptyCoroutineContext, RuntimeException("delegated"))
            val factory = CoroutineExceptionHandler { _, _ -> }
            factory.handleException(EmptyCoroutineContext, RuntimeException("factory"))
            val combined: CoroutineContext = collector + EmptyCoroutineContext
            combined[CoroutineExceptionHandler]
            combined[CoroutineExceptionHandler.Key]
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let fqName = ["kotlinx", "coroutines", "CoroutineExceptionHandler"].map(ctx.interner.intern)
        let nominals = sema.symbols.lookupAll(fqName: fqName).filter { id in
            let kind = sema.symbols.symbol(id)?.kind
            return kind == .interface || kind == .class
        }
        let handlerSymbol = try #require(nominals.first)
        #expect(
            sema.symbols.symbol(handlerSymbol)?.kind == .interface,
            "Expected CoroutineExceptionHandler to be an interface so `by`-delegation and `object :` implementations resolve (KUU-4361)"
        )
        #expect(
            sema.symbols.lookupAll(fqName: fqName + [ctx.interner.intern("<init>")]).isEmpty,
            "Interfaces must not carry the synthetic runtime-box constructor"
        )

        let companion = try #require(sema.symbols.companionObjectSymbol(for: handlerSymbol))
        #expect(sema.symbols.externalLinkName(for: companion) == runtimeABIName(.exceptionHandlerKey))
        let handleException = try #require(sema.symbols.lookup(
            fqName: fqName + [ctx.interner.intern("handleException")]
        ))
        #expect(sema.symbols.externalLinkName(for: handleException) == "kk_exception_handler_invoke")
    }
}
