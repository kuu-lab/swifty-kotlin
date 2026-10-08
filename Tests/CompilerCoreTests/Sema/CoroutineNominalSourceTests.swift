@testable import CompilerCore
import Testing

@Suite
struct CoroutineNominalSourceTests {
    @Test
    func explicitStartResolvesWithoutBundledStdlib() throws {
        try withTemporaryFile(contents: """
        import kotlinx.coroutines.*
        fun startJob(job: Job): Boolean = job.start()
        fun startDeferred(deferred: Deferred): Boolean = deferred.start()
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let start = try #require(sema.symbols.lookup(fqName: [
                "kotlinx", "coroutines", "Job", "start",
            ].map(ctx.interner.intern)))
            #expect(sema.symbols.externalLinkName(for: start) == runtimeABIName(.jobStart))
            #expect(sema.symbols.symbol(start)?.flags.contains(.synthetic) == true)
        }
    }

    @Test
    func nominalHierarchyAndConstructorsResolveFromBundledSource() throws {
        // Keep the qualified super-call regression independent of JobImpl's body.
        let source = """
        import kotlin.coroutines.*
        import kotlinx.coroutines.*
        import kotlinx.coroutines.internal.ScopeCoroutine

        class JobSupportProbe : JobSupport(true), CompletableJob {
            override fun complete(): Boolean = complete(Unit)
            override fun completeExceptionally(exception: Throwable): Boolean =
                super<JobSupport>.completeExceptionally(exception)
        }

        fun job(parent: Job?): CompletableJob = JobImpl(parent)
        fun child(job: JobSupport): ChildJob = job
        fun parent(job: JobSupport): ParentJob = job
        fun context(job: JobSupport): CoroutineContext.Element = job
        fun continuation(coroutine: AbstractCoroutine<String>): Continuation<String> = coroutine
        fun scope(coroutine: AbstractCoroutine<String>): CoroutineScope = coroutine
        fun contravariant(coroutine: AbstractCoroutine<Any>): AbstractCoroutine<String> = coroutine
        fun scoped(context: CoroutineContext, continuation: Continuation<String>): AbstractCoroutine<String> =
            ScopedCoroutine<String>(context, continuation)
        fun canonical(context: CoroutineContext, continuation: Continuation<String>): AbstractCoroutine<String> =
            ScopeCoroutine<String>(context, continuation)
        fun dispatched(context: CoroutineContext, continuation: Continuation<String>): ScopedCoroutine<String> =
            DispatchedCoroutine<String>(context, continuation)
        fun immediate(dispatcher: MainCoroutineDispatcher): CoroutineDispatcher = dispatcher.immediate
        fun handle(): ChildHandle = NonDisposableHandle
        fun disposable(): DisposableHandle = NonDisposableHandle
        fun task(task: DispatchedTask<String>): Continuation<String> = task.delegate
        fun complete(job: CompletableJob): Boolean = job.complete()
        fun factory(): CompletableJob = Job()
        fun supervisor(): CompletableJob = SupervisorJob()
        fun deferredJob(deferred: Deferred): Job = deferred
        fun startJob(job: Job): Boolean = job.start()
        fun startDeferred(deferred: Deferred<Int>): Boolean = deferred.start()
        fun startCompletable(job: CompletableJob): Boolean = job.start()
        fun startCompletableDeferred(deferred: CompletableDeferred<Int>): Boolean = deferred.start()
        fun startSupport(job: JobSupport): Boolean = job.start()
        fun producerScope(scope: kotlinx.coroutines.channels.ProducerScope<Int>): CoroutineContext = scope.coroutineContext
        fun actorScope(scope: kotlinx.coroutines.channels.ActorScope<Int>): CoroutineContext = scope.coroutineContext
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map { diagnostic in
            guard let range = diagnostic.primaryRange else { return diagnostic.message }
            return "\(ctx.sourceManager.path(of: range.start.file)): \(ctx.sourceManager.slice(range)): \(diagnostic.message)"
        }
        #expect(!ctx.diagnostics.hasError, "\(errors)")
        let sema = try #require(ctx.sema)
        let root = ["kotlinx", "coroutines"].map(ctx.interner.intern)
        let expected: [(String, SymbolKind)] = [
            ("Job", .interface), ("CoroutineScope", .interface),
            ("ChildJob", .interface), ("ParentJob", .interface),
            ("ChildHandle", .interface), ("CompletableJob", .interface),
            ("JobSupport", .class), ("JobImpl", .class),
            ("AbstractCoroutine", .class), ("ScopedCoroutine", .class),
            ("DispatchedCoroutine", .class), ("DispatchedTask", .class),
            ("CoroutineDispatcher", .class), ("MainCoroutineDispatcher", .class),
            ("NonDisposableHandle", .object),
        ]
        for (name, kind) in expected {
            let nominals = sema.symbols.lookupAll(fqName: root + [ctx.interner.intern(name)]).filter {
                sema.symbols.symbol($0)?.kind == kind
            }
            #expect(nominals.count == 1, "\(name) must have exactly one nominal declaration")
            let symbol = try #require(nominals.first)
            let info = try #require(sema.symbols.symbol(symbol))
            #expect(!info.flags.contains(.synthetic), "\(name) must be source-backed")
            #expect(sema.symbols.sourceFileID(for: symbol) != nil)
        }
        let abstractCoroutine = try #require(sema.symbols.lookup(
            fqName: root + [ctx.interner.intern("AbstractCoroutine")]
        ))
        #expect(sema.types.nominalTypeParameterVariances(for: abstractCoroutine) == [.in])
        let jobSupport = try #require(sema.symbols.lookup(fqName: root + [ctx.interner.intern("JobSupport")]))
        #expect(sema.symbols.symbol(jobSupport)?.flags.contains(.abstractType) == true)
        let ast = try #require(ctx.ast)
        let jobSupportCalls = memberCallExprIDs(named: "completeExceptionally", in: ast, interner: ctx.interner).filter { call in
            guard let range = ast.arena.exprRange(call),
                  ctx.options.inputs.contains(ctx.sourceManager.path(of: range.start.file)),
                  case let .memberCall(receiver, _, _, _, _) = ast.arena.expr(call),
                  case let .superRef(qualifier?, _) = ast.arena.expr(receiver)
            else { return false }
            return ctx.interner.resolve(qualifier) == "JobSupport"
        }
        #expect(jobSupportCalls.count == 1)
        for call in jobSupportCalls {
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(sema.symbols.parentSymbol(for: binding.chosenCallee) == jobSupport)
        }
        for name in ["Job", "ChildJob", "ParentJob"] {
            let parent = try #require(sema.symbols.lookup(fqName: root + [ctx.interner.intern(name)]))
            #expect(sema.symbols.directSupertypes(for: jobSupport).contains(parent))
        }
        let job = try #require(sema.symbols.lookupAll(fqName: root + [ctx.interner.intern("Job")]).first {
            sema.symbols.symbol($0)?.kind == .interface
        })
        let active = try #require(sema.symbols.lookup(fqName: root + [ctx.interner.intern("Job"), ctx.interner.intern("isActive")]))
        #expect(sema.symbols.parentSymbol(for: active) == job)
        #expect(sema.symbols.externalLinkName(for: active) == runtimeABIName(.jobIsActive))
        let starts = sema.symbols.lookupAll(fqName: root + [ctx.interner.intern("Job"), ctx.interner.intern("start")])
        #expect(starts.count == 1)
        let start = try #require(starts.first)
        #expect(sema.symbols.parentSymbol(for: start) == job)
        #expect(sema.symbols.externalLinkName(for: start) == runtimeABIName(.jobStart))
        let signature = try #require(sema.symbols.functionSignature(for: start))
        #expect(signature.parameterTypes.isEmpty)
        #expect(signature.returnType == sema.types.booleanType)
        #expect(!signature.isSuspend)
        #expect(sema.symbols.sourceFileID(for: start) != nil)
    }
}
