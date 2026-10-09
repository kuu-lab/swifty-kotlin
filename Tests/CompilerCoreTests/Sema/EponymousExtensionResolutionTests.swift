#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct EponymousExtensionResolutionTests {
    @Test
    func implicitMemberRemainsVisibleBesideSameNamedExtension() throws {
        let source = """
        class Chan {
            fun cancel(cause: Throwable?) {}
        }
        fun Chan.cancel() {}
        fun Chan.read2() {
            cancel(null)
            try { cancel(null) } catch (cause: Throwable) { cancel(cause) }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected implicit member calls: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let member = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("Chan"), ctx.interner.intern("cancel"),
        ]))
        let calls = sema.bindings.callBindings.filter { $0.value.chosenCallee == member }
        #expect(calls.count == 3)
        #expect(calls.keys.allSatisfy { sema.bindings.implicitReceiverMemberNames[$0] == ctx.interner.intern("cancel") })
    }

    @Test
    func sameNamedExtensionDelegatesToDifferentReceiver() throws {
        let source = """
        import kotlin.coroutines.cancellation.CancellationException
        class Job
        fun Job.getCancellationException(): CancellationException = CancellationException("job")
        interface ChannelJob { val job: Job }
        fun ChannelJob.getCancellationException(): CancellationException = job.getCancellationException()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected extension delegation: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "getCancellationException", in: ast, interner: ctx.interner).filter {
            guard case let .memberCall(_, _, _, _, range) = ast.arena.expr($0) else { return false }
            return ctx.sourceManager.origin(of: range.start.file) == .user
        }
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        let binding = try #require(sema.bindings.callBinding(for: call))
        let receiver = try #require(sema.symbols.functionSignature(for: binding.chosenCallee)?.receiverType)
        let job = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Job")]))
        guard case let .classType(receiverClass) = sema.types.kind(of: receiver) else {
            Issue.record("Expected a nominal Job extension receiver")
            return
        }
        #expect(receiverClass.classSymbol == job)
    }

    @Test
    func sameNamedExtensionDelegatesToInheritedMember() throws {
        let source = """
        open class BaseChan {
            fun cancel(cause: Throwable?): Int = 1
        }
        class Chan : BaseChan()
        fun Chan.cancel(): Int = cancel(null)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected inherited member delegation: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let member = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("BaseChan"), ctx.interner.intern("cancel"),
        ]))
        let call = try #require(sema.bindings.callBindings.first { $0.value.chosenCallee == member }?.key)
        #expect(sema.bindings.implicitReceiverMemberNames[call] == ctx.interner.intern("cancel"))
    }

    @Test(arguments: [true, false])
    func delegationRespectsExtensionImports(importExtension: Bool) throws {
        let declarations = """
        package library
        class Job
        fun Job.getCancellationException(): Int = 7
        """
        let usage = """
        package consumer
        import library.Job
        \(importExtension ? "import library.getCancellationException" : "")
        interface ChannelJob { val job: Job }
        fun ChannelJob.getCancellationException(): Int = job.getCancellationException()
        """
        let ctx = makeContextFromSources([declarations, usage])
        try runSema(ctx)
        if importExtension {
            #expect(!ctx.diagnostics.hasError, "Expected imported delegation: \(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let delegate = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("library"), ctx.interner.intern("getCancellationException"),
            ]))
            #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == delegate })
        } else {
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "An unimported extension must remain unavailable: \(errors)")
        }
    }
}
#endif
