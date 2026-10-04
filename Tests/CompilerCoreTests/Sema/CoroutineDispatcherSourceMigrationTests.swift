@testable import CompilerCore
import Testing

@Suite
struct CoroutineDispatcherSourceMigrationTests {
    @Test
    func dispatcherSurfaceIsSourceBacked() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.*
        import java.util.concurrent.Executor
        import java.util.concurrent.ExecutorService

        fun views(dispatcher: CoroutineDispatcher, executor: Executor, service: ExecutorService) {
            val io: CoroutineDispatcher = Dispatchers.IO
            val unconfined: CoroutineDispatcher = Dispatchers.Unconfined
            val main: CoroutineDispatcher = Dispatchers.Main.immediate
            val limited: CoroutineDispatcher = dispatcher.limitedParallelism(parallelism = 2)
            val single: CoroutineDispatcher = newSingleThreadContext(name = "single")
            val fixed: CoroutineDispatcher = newFixedThreadPoolContext(nThreads = 2, name = "fixed")
            val scheduled: CoroutineDispatcher = newScheduledThreadPoolContext(nThreads = 2, name = "scheduled")
            val adapted: CoroutineDispatcher = executor.asCoroutineDispatcher()
            val adaptedService: CoroutineDispatcher = service.asCoroutineDispatcher()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let package = ["kotlinx", "coroutines"].map(ctx.interner.intern)
        let declarations: [(String, String)] = [
            ("Dispatchers", "Dispatchers.kt"),
            ("immediate", "CoroutineDispatcher.kt"),
            ("limitedParallelism", "CoroutineDispatcher.kt"),
            ("newSingleThreadContext", "ThreadPoolDispatcher.kt"),
            ("newFixedThreadPoolContext", "ThreadPoolDispatcher.kt"),
            ("newScheduledThreadPoolContext", "ThreadPoolDispatcher.kt"),
            ("asCoroutineDispatcher", "Executors.kt"),
        ]
        for (name, fileName) in declarations {
            let symbols = sema.symbols.lookupAll(fqName: package + [ctx.interner.intern(name)])
            #expect(symbols.count == (name == "asCoroutineDispatcher" ? 2 : 1))
            for symbol in symbols {
                let info = try #require(sema.symbols.symbol(symbol))
                #expect(!info.flags.contains(.synthetic))
                let file = try #require(sema.symbols.sourceFileID(for: symbol))
                #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlinx/coroutines/\(fileName)")
            }
        }
        for name in ["Default", "IO", "Unconfined", "Main"] {
            let symbols = sema.symbols.lookupAll(fqName: package + ["Dispatchers", name].map(ctx.interner.intern))
            #expect(symbols.count == 1)
            let symbol = try #require(symbols.first)
            #expect(sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == false)
        }
    }
}
