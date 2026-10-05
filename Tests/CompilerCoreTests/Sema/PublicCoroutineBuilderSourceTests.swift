#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct PublicCoroutineBuilderSourceTests {
    @Test
    func allFiveBuildersHaveOneSourceOwner() throws {
        let ctx = makeContextFromSource("""
        import kotlin.coroutines.*
        fun prepare(block: suspend () -> Int, completion: Continuation<Int>): Continuation<Unit> =
            block.createCoroutine(completion)
        fun prepareReceiver(block: suspend String.() -> Int, completion: Continuation<Int>): Continuation<Unit> =
            block.createCoroutine("abc", completion)
        fun start(block: suspend () -> Int, completion: Continuation<Int>) = block.startCoroutine(completion)
        fun startReceiver(block: suspend String.() -> Int, completion: Continuation<Int>) =
            block.startCoroutine("abc", completion)
        suspend fun value(): Int = suspendCoroutine<Int> { continuation -> continuation.resume(42) }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")
        let symbols = try #require(ctx.sema?.symbols)
        let prefix = ["kotlin", "coroutines"].map(ctx.interner.intern)
        for (name, count) in [("startCoroutine", 2), ("createCoroutine", 2), ("suspendCoroutine", 1)] {
            let overloads = symbols.lookupAll(fqName: prefix + [ctx.interner.intern(name)])
            #expect(overloads.count == count)
            for symbol in overloads {
                #expect(symbols.isSourceBackedSymbol(symbol))
                #expect(symbols.externalLinkName(for: symbol) == nil)
                if name != "suspendCoroutine" {
                    #expect(symbols.symbol(symbol)?.flags.contains(.inlineFunction) == false)
                }
                let file = try #require(symbols.sourceFileID(for: symbol))
                #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/coroutines/Continuation.kt")
            }
        }
    }
}
#endif
