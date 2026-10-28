@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-3655: Channel members resolve through projected type-parameter bounds.
@Suite
struct ChannelUpperBoundMemberTests {
    private func compile(_ source: String, useArtifact: Bool) throws -> CompilationContext {
        if useArtifact { TestStdlibCache.shared.prepare() }
        var result: CompilationContext?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                emit: .executable,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            result = ctx
        }
        return try #require(result)
    }

    @Test(arguments: [false, true])
    func channelUpperBoundMembersUseReadableElementTypesAndKeepControls(useArtifact: Bool) throws {
        let ctx = try compile("""
        import kotlinx.coroutines.channels.Channel

        suspend fun <C : Channel<Int>> allowed(ch: C): Int = ch.receive()
        suspend fun <C : Channel<out Int>> outProjection(ch: C): Int = ch.receive()
        suspend fun <C : Channel<*>> starProjection(ch: C): Any? = ch.receive()
        suspend fun <C : Channel<in Int>> inProjection(ch: C): Any? = ch.receive()
        fun <C : Any> nonChannel(ch: C) { ch.receive() }
        fun <C : Channel<Int>> nonSuspend(ch: C) { ch.receive() }
        """, useArtifact: useArtifact)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(
            named: "receive",
            in: ast,
            path: ctx.options.inputs[0],
            ctx: ctx,
            interner: ctx.interner
        )
        #expect(calls.count == 6)
        guard calls.count == 6 else { return }

        #expect(calls.prefix(4).map { sema.bindings.exprType(for: $0) } == [
            sema.types.intType,
            sema.types.intType,
            sema.types.nullableAnyType,
            sema.types.nullableAnyType,
        ])
        for call in calls.prefix(4) {
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            #expect(sema.symbols.functionSignature(for: chosen)?.isSuspend == true)
        }

        #expect(sema.bindings.callBinding(for: calls[4]) == nil,
                "A non-Channel upper bound must not gain receive()")
        let nonSuspendCallee = try #require(sema.bindings.callBinding(for: calls[5])?.chosenCallee)
        #expect(sema.symbols.functionSignature(for: nonSuspendCallee)?.isSuspend == true)

        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0308" },
                "A Channel-bound receive call must still require a suspend context: \(ctx.diagnostics.diagnostics)")
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0002" || $0.code == "KSWIFTK-SEMA-0024"
        }, "The non-Channel control must reject receive(): \(ctx.diagnostics.diagnostics)")
    }
}
