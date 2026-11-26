#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct BundledStdlibSourceShadowingTests {
    private let declarations = """
    package kotlinx.coroutines.channels

    import kotlinx.coroutines.*
    import kotlin.coroutines.*

    public interface SendChannel<in E> {
        public suspend fun send(element: E)
    }

    public interface ProducerScope<in E> : CoroutineScope, SendChannel<E> {
        public val channel: SendChannel<E>
    }

    public interface ReceiveChannel<out E>

    public fun <E> CoroutineScope.produce(
        context: CoroutineContext = EmptyCoroutineContext,
        capacity: Int = 0,
        block: suspend ProducerScope<E>.() -> Unit
    ): ReceiveChannel<E> = TODO()

    public fun <E> CoroutineScope.produce(
        context: CoroutineContext = EmptyCoroutineContext,
        capacity: Int = 0,
        start: CoroutineStart = CoroutineStart.DEFAULT,
        onCompletion: CompletionHandler? = null,
        block: suspend ProducerScope<E>.() -> Unit
    ): ReceiveChannel<E> = TODO()
    """

    private let consumer = """
    package kotlinx.coroutines.flow

    import kotlinx.coroutines.*
    import kotlinx.coroutines.channels.*

    internal fun CoroutineScope.fixedPeriodTicker(): ReceiveChannel<Unit> {
        return produce(capacity = 0) {
            channel.send(Unit)
        }
    }
    """

    private let valPositionConsumer = """
    package kotlinx.coroutines.flow

    import kotlinx.coroutines.*
    import kotlinx.coroutines.channels.*

    internal fun CoroutineScope.valPositionTicker(): ReceiveChannel<Unit> {
        val values = produce(capacity = 0) {
            channel.send(Unit)
        }
        return values
    }

    internal fun CoroutineScope.valPositionNoCapacity(): ReceiveChannel<Unit> {
        val values = produce {
            send(Unit)
        }
        return values
    }

    internal fun CoroutineScope.valPositionFullOverload(): ReceiveChannel<Unit> {
        val values = produce(
            context = EmptyCoroutineContext,
            capacity = 0,
            start = CoroutineStart.DEFAULT
        ) {
            channel.send(Unit)
        }
        return values
    }
    """

    private func assertProduceCallsBindSourceDeclared(
        _ ctx: CompilationContext,
        expectedCount: Int
    ) throws {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var chosenCount = 0
        for index in ast.arena.exprs.indices {
            let call = ExprID(rawValue: Int32(index))
            guard case let .call(callee, _, _, _) = ast.arena.expr(call),
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  ctx.interner.resolve(name) == "produce"
            else {
                continue
            }
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let symbol = try #require(sema.symbols.symbol(chosen))
            #expect(
                !symbol.flags.contains(.importedLibrary),
                "produce resolved to imported symbol \(symbol.fqName)"
            )
            chosenCount += 1
        }
        #expect(chosenCount == expectedCount)
    }

    @Test
    func sourceProduceShadowsBundledStdlibProduce() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSources(
            [declarations, consumer],
            allowDefaultStdlibLibrary: true
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")

        try assertProduceCallsBindSourceDeclared(ctx, expectedCount: 1)
    }

    private let ensureActiveDeclarations = """
    package kotlinx.coroutines

    import kotlin.coroutines.CoroutineContext

    public fun CoroutineContext.ensureActive() {}
    """

    private let ensureActiveConsumer = """
    package kotlinx.coroutines

    import kotlin.coroutines.CoroutineContext

    fun check(newContext: CoroutineContext) {
        newContext.ensureActive()
    }
    """

    @Test
    func sourceEnsureActiveShadowsBundledStdlibEnsureActive() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSources(
            [ensureActiveDeclarations, ensureActiveConsumer],
            allowDefaultStdlibLibrary: true
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var chosenCount = 0
        for index in ast.arena.exprs.indices {
            let call = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(call),
                  ctx.interner.resolve(callee) == "ensureActive"
            else {
                continue
            }
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let symbol = try #require(sema.symbols.symbol(chosen))
            #expect(
                !symbol.flags.contains(.importedLibrary),
                "ensureActive resolved to imported symbol \(symbol.fqName)"
            )
            chosenCount += 1
        }
        #expect(chosenCount == 1)
    }

    @Test
    func sourceProduceBindsInValPosition() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSources(
            [declarations, valPositionConsumer],
            allowDefaultStdlibLibrary: true
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")

        try assertProduceCallsBindSourceDeclared(ctx, expectedCount: 3)
    }
}
#endif
