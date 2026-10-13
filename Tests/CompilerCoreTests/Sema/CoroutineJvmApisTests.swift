@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

@Suite
struct CoroutineJvmApisTests {
    @Test
    func testJvmCoroutineApis() throws {
        let source = """
        import java.util.concurrent.Executor
        import java.util.concurrent.ExecutorService
        import java.util.concurrent.CompletableFuture
        import java.util.concurrent.CompletionStage
        import kotlinx.coroutines.*
        import kotlinx.coroutines.debug.DebugProbes
        import kotlinx.coroutines.future.*

        class CustomDispatcher(override val executor: Executor) : ExecutorCoroutineDispatcher() {
            override fun close() {}
        }

        fun testExecutors(e: Executor, es: ExecutorService, d: CoroutineDispatcher) {
            val d1: CoroutineDispatcher = e.asCoroutineDispatcher()
            val d2: ExecutorCoroutineDispatcher = es.asCoroutineDispatcher()
            val exec: Executor = d.asExecutor()
            val custom = CustomDispatcher(e)
            custom.close()
        }

        fun testBlockingEventLoop() {
            val loop = BlockingEventLoop()
            val loopWithThread = BlockingEventLoop("main")
        }

        suspend fun testInterruptible(): Int {
            return runInterruptible { 42 }
        }

        fun testDebugProbes() {
            DebugProbes.install()
            DebugProbes.enableCreationStackTraces = true
            DebugProbes.sanitizeStackTraces = true
            val installed: Boolean = DebugProbes.isInstalled
            DebugProbes.dumpCoroutines()
            val list = DebugProbes.dumpCoroutinesInfo()
            val res = DebugProbes.withDebugProbes { 123 }
            DebugProbes.uninstall()
        }

        suspend fun testFutureInterop(d: Deferred, j: Job, cs: CompletionStage<String>, cf: CompletableFuture<Int>) {
            val f1: CompletableFuture<Any?> = d.asCompletableFuture()
            val f2: CompletableFuture<Unit> = j.asCompletableFuture()
            val def: Deferred = cs.asDeferred()
            val s: String = cs.await()
            val f3: CompletableFuture<Int> = future { 10 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "JVM coroutine APIs must type-check: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func testWildcardImportTypeResolutionDisambiguatesSameNameAcrossPackages() throws {
        let source = """
        package test
        import kotlin.native.concurrent.*
        fun preserveFuture(value: Future<Int>): Future<Int> = value
        """
        TestStdlibCache.shared.prepare()
        try withTemporaryFile(contents: source) { path in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let options = CompilerOptions(
                moduleName: "TestModule",
                inputs: [path],
                outputPath: destination,
                emit: .kirDump,
                target: TargetTriple.hostDefault(),
                includeStdlib: true,
                stdlibLibraryPath: CompilerOptions.defaultStdlibLibraryPath
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try LoadSourcesPhase().run(ctx)
            try LexPhase().run(ctx)
            try ParsePhase().run(ctx)
            try BuildASTPhase().run(ctx)
            try SemaPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError, "preserveFuture must type-check without error: \(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let syms = sema.symbols.lookupByShortName(ctx.interner.intern("preserveFuture"))
            let fnSymbol = try #require(syms.first)
            let sig = try #require(sema.symbols.functionSignature(for: fnSymbol))
            let paramType = sig.parameterTypes[0]
            guard case let .classType(ct) = sema.types.kind(of: paramType), let cInfo = sema.symbols.symbol(ct.classSymbol) else {
                Issue.record("Expected class type for parameter")
                return
            }
            let fq = cInfo.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
            #expect(fq == "kotlin.native.concurrent.Future")
        }
    }
}
