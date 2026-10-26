@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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
        struct DeclarationExpectation {
            let name: String
            let parentName: String?
            let fileName: String
            let expectedSymbolCount: Int
            init(_ name: String, parent: String? = nil, fileName: String, expectedSymbolCount: Int) {
                self.name = name
                self.parentName = parent
                self.fileName = fileName
                self.expectedSymbolCount = expectedSymbolCount
            }
        }
        let declarations: [DeclarationExpectation] = [
            DeclarationExpectation("Dispatchers", fileName: "Dispatchers.kt", expectedSymbolCount: 1),
            DeclarationExpectation("immediate", parent: "MainCoroutineDispatcher", fileName: "MainCoroutineDispatcher.kt", expectedSymbolCount: 1),
            DeclarationExpectation("limitedParallelism", fileName: "CoroutineDispatcher.kt", expectedSymbolCount: 1),
            DeclarationExpectation("newSingleThreadContext", fileName: "ThreadPoolDispatcher.kt", expectedSymbolCount: 1),
            DeclarationExpectation("newFixedThreadPoolContext", fileName: "ThreadPoolDispatcher.kt", expectedSymbolCount: 1),
            DeclarationExpectation("newScheduledThreadPoolContext", fileName: "ThreadPoolDispatcher.kt", expectedSymbolCount: 1),
            DeclarationExpectation("asCoroutineDispatcher", fileName: "Executors.kt", expectedSymbolCount: 2),
        ]
        for declaration in declarations {
            let fqName = package
                + (declaration.parentName.map { [ctx.interner.intern($0)] } ?? [])
                + [ctx.interner.intern(declaration.name)]
            let symbols = sema.symbols.lookupAll(fqName: fqName)
            #expect(symbols.count == declaration.expectedSymbolCount)
            for symbol in symbols {
                let info = try #require(sema.symbols.symbol(symbol))
                #expect(!info.flags.contains(.synthetic))
                let file = try #require(sema.symbols.sourceFileID(for: symbol))
                #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlinx/coroutines/\(declaration.fileName)")
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
