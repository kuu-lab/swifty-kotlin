#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-4305: when the module under compilation declares its own
/// `kotlinx.coroutines.channels.produce` overloads (upstream
/// kotlinx-coroutines sources), the bundled stdlib artifact's simplified
/// `produce(capacity, block)` twin must not win overload resolution — its
/// serialized return type is the bundled `Channel<E>`, which cannot satisfy
/// the source `ReceiveChannel<Unit>` the module declares.
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

    /// KUU-4313: the same source-declared overloads must also win when the
    /// call sits in val position — `E` is recoverable only from the builder
    /// lambda's `send` arguments there, which ordinary overload resolution
    /// cannot see.
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

        // The chosen callee must be one of the source-declared overloads,
        // not the bundled stdlib `produce(capacity, block)` twin.
        try assertProduceCallsBindSourceDeclared(ctx, expectedCount: 1)
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

        // All val-position calls must bind a source-declared overload with
        // the element type recovered from the lambda's `send` arguments —
        // `return values` against `ReceiveChannel<Unit>` would fail if the
        // inferred element type were not `Unit`.
        try assertProduceCallsBindSourceDeclared(ctx, expectedCount: 3)
    }
}
#endif
