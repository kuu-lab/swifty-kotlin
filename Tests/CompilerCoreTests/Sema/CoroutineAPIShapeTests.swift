@testable import CompilerCore
import Testing

@Suite
struct CoroutineAPIShapeTests {
    @Test
    func explicitJobImportResolvesFactoryAlongsideInterface() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.Job
        fun f() = Job()
        fun child(parent: Job?) = Job(parent)
        """, allowDefaultStdlibLibrary: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func jobFactoriesAndLaunchMatchPublicCoroutineShape() throws {
        let ctx = makeContextFromSource("""
        import kotlin.coroutines.*
        import kotlinx.coroutines.*

        fun factory(): CompletableJob = Job()
        fun child(parent: Job?): CompletableJob = Job(parent = parent)
        fun supervisor(parent: Job?): CompletableJob = SupervisorJob(parent)
        fun launchValue(scope: CoroutineScope, context: CoroutineContext,
                        block: suspend CoroutineScope.() -> Unit): Job =
            scope.launch(context = context, start = CoroutineStart.LAZY, block = block)
        suspend fun probe(scope: CoroutineScope, context: CoroutineContext, job: Job) {
            scope.launch(context) {
                val receiver: CoroutineScope = this
                val ownContext: CoroutineContext = this.coroutineContext
                launch(ownContext) { this.coroutineContext.job.ensureActive() }
            }.join()
            scope.launch(start = CoroutineStart.UNDISPATCHED) { }.join()
            scope.launch { }.join()
            val children: kotlin.sequences.Sequence<Job> = job.children
            val handle: DisposableHandle = job.invokeOnCompletion { cause -> println(cause) }
            job.cancelChildren()
            job.getCancellationException()
            job.join()
        }
        """, allowDefaultStdlibLibrary: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let root = ["kotlinx", "coroutines"].map(ctx.interner.intern)
        let launches = sema.symbols.lookupAll(fqName: root + [ctx.interner.intern("launch")])
        #expect(launches.count == 1)
        let launch = try #require(launches.first)
        #expect(sema.symbols.isSourceBackedSymbol(launch))
        let signature = try #require(sema.symbols.functionSignature(for: launch))
        #expect(signature.valueParameterHasDefaultValues == [true, true, false])
        #expect(signature.parameterTypes.count == 3)
        guard case let .classType(contextType) = sema.types.kind(of: signature.parameterTypes[0]) else {
            Issue.record("Expected a CoroutineContext parameter")
            return
        }
        let contextName = sema.symbols.symbol(contextType.classSymbol)?.fqName.map(ctx.interner.resolve)
        #expect(contextName == ["kotlin", "coroutines", "CoroutineContext"])
        guard case let .functionType(block) = sema.types.kind(of: signature.parameterTypes[2]) else {
            Issue.record("Expected a suspend receiver block")
            return
        }
        #expect(block.receiver == signature.receiverType)
        #expect(block.isSuspend)
        #expect(block.returnType == sema.types.unitType)
        let jobs = sema.symbols.lookupAll(fqName: root + [ctx.interner.intern("Job")]).filter {
            let kind = sema.symbols.symbol($0)?.kind
            return kind == .interface || kind == .class
        }
        #expect(jobs.count == 1)
        let job = try #require(jobs.first)
        let jobKind = sema.symbols.symbol(job)?.kind
        #expect(jobKind == .interface)
    }
}
