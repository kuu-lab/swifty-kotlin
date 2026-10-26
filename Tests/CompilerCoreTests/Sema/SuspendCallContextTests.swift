@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct SuspendCallContextTests {
    private func diagnostics(_ source: String, includeStdlib: Bool = false) throws -> DiagnosticEngine {
        var result: DiagnosticEngine?
        let input = includeStdlib ? source : "fun println(value: Any?) {}\n" + source
        try withTemporaryFile(contents: input) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: includeStdlib)
            try runSema(ctx)
            result = ctx.diagnostics
        }
        return try requireTestValue(result, "Expected Sema diagnostics")
    }

    @Test
    func issueReproducerRejectsBothCallsButAllowsReference() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        suspend fun caller() = sf()
        fun main() {
            val f: suspend () -> Int = ::sf
            println(f())
            println(::sf)
            println(sf())
        }
        """)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2, "\(result.diagnostics)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0308" })
        #expect(errors.allSatisfy { $0.primaryRange != nil })
    }

    @Test
    func memberExtensionAndExplicitInvokeAreRejected() throws {
        let result = try diagnostics("""
        class Worker { suspend fun work() = 1 }
        class Holder(val f: suspend () -> Int)
        suspend fun String.work() = 2
        fun bad(w: Worker, f: suspend () -> Int, h: Holder) {
            w.work()
            "test".work()
            f.invoke()
            h.f()
            val ext: suspend String.() -> Int = { 1 }
            "test".ext()
        }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0308" }.count == 5, "\(result.diagnostics)")
    }

    @Test
    func suspendFunctionsAndSuspendLambdasAreAccepted() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        suspend fun caller(f: suspend () -> Int) {
            sf()
            f()
            f.invoke()
        }
        fun setup() {
            val f: suspend () -> Int = { sf() }
            val ref = ::sf
        }
        """)
        #expect(!result.hasError, "\(result.diagnostics)")
    }

    @Test
    func coroutineContextPropertyRequiresSuspensionContext() throws {
        let result = try diagnostics("""
        fun main() { println(kotlin.coroutines.coroutineContext != null) }
        """, includeStdlib: true)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(result.diagnostics)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0313")
        #expect(errors.first?.message == "Suspend property 'val coroutineContext: CoroutineContext' can only be accessed from a coroutine or suspend function.")
    }

    @Test
    func coroutineContextPropertyIsAllowedInSuspendContextAndShadowingIsUnaffected() throws {
        let result = try diagnostics("""
        import kotlin.coroutines.coroutineContext
        suspend fun currentContext() = coroutineContext
        fun shadowed(coroutineContext: Int) = coroutineContext
        class Holder(val coroutineContext: Int) {
            fun read() = coroutineContext
        }
        fun localShadowed() {
            val coroutineContext = 1
            println(coroutineContext)
        }
        """, includeStdlib: true)
        #expect(!result.hasError, "\(result.diagnostics)")
    }

    @Test
    func suspendSamLambdaSuppliesItsOwnSuspensionContext() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        fun interface SuspendAction { suspend fun run() }
        fun accept(action: SuspendAction) {}
        fun setup() { accept { sf() } }
        """)
        #expect(!result.hasError, "\(result.diagnostics)")
    }

    @Test
    func explicitSuspendSamConstructorSuppliesItsOwnSuspensionContext() throws {
        let result = try diagnostics("""
        suspend fun sf(): Int = 42
        fun interface SuspendAction { suspend fun run(): Int }
        fun setup() { val action = SuspendAction { sf() } }
        """)
        #expect(!result.hasError, "\(result.diagnostics)")
    }

    @Test
    func nonSuspendSamLambdaDoesNotInheritSuspensionContext() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        fun interface OrdinaryAction { fun run() }
        fun accept(action: OrdinaryAction) {}
        fun ordinaryCaller() { accept { sf() } }
        suspend fun suspendCaller() { accept { sf() } }
        """)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2, "\(result.diagnostics)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0308" })
    }

    @Test
    func flowCollectSuspendSamMinimumReproducerIsAccepted() throws {
        let result = try diagnostics("""
        interface Flow<out T> {
            suspend fun collect(collector: FlowCollector<T>)
        }
        fun interface FlowCollector<in T> {
            suspend fun emit(value: T)
        }
        inline fun <T, R> Flow<T>.transform(
            crossinline transform: suspend FlowCollector<R>.(value: T) -> Unit
        ): Flow<R> = object : Flow<R> {
            override suspend fun collect(collector: FlowCollector<R>) {
                this@transform.collect label@{ value ->
                    return@label collector.transform(value)
                }
            }
        }
        fun box(): String = "OK"
        """)
        #expect(!result.hasError, "\(result.diagnostics)")
    }

    @Test
    func callableLocalDoesNotHideApplicableTrailingLambdaExtension() throws {
        let result = try diagnostics("""
        class Flow<T>
        fun <T, R> Flow<T>.transform(action: (T) -> R): Flow<R> = Flow()
        inline fun <T, R> Flow<T>.map(transform: (T) -> R): Flow<R> =
            transform { value -> transform(value) }
        """)
        #expect(!result.hasError, "\(result.diagnostics)")
    }

    @Test
    func coroutineBuildersProvideSuspensionContexts() throws {
        let result = try diagnostics("""
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*
        suspend fun sf() = 1
        fun setup() {
            runBlocking {
                sf()
                launch { sf() }.join()
                async { sf() }.await()
            }
            val values = flow { emit(sf()) }
        }
        """, includeStdlib: true)
        #expect(!result.hasError, "\(result.diagnostics)")
    }

    @Test
    func coroutineBuildersAndFlowOperatorsProvideSuspensionContextsWithoutExplicitImport() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        fun setup() {
            runBlocking {
                sf()
            }
        }
        """, includeStdlib: true)
        #expect(!result.hasError, "\(result.diagnostics)")
    }

    @Test
    func ordinaryNestedFunctionsAndEscapingLambdasDoNotInheritSuspension() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        fun consume(block: () -> Int) = block()
        suspend fun outer() {
            fun local() = sf()
            val stored = { sf() }
            consume { sf() }
            suspend fun localSuspend() = sf()
        }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0308" }.count == 3, "\(result.diagnostics)")
    }

    @Test
    func defaultsAndNominalInitializersCannotInheritSuspension() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        suspend fun defaults(x: Int = sf()) {}
        suspend fun outer() {
            val obj = object {
                val x = sf()
                init { sf() }
                val permitted: suspend () -> Int = { sf() }
            }
            class Local {
                val x = sf()
                init { sf() }
                constructor() { sf() }
            }
        }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0308" }.count == 6, "\(result.diagnostics)")
    }

    @Test
    func operatorSyntaxChecksTheResolvedSuspendCallee() throws {
        let result = try diagnostics("""
        class Operand {
            suspend operator fun plus(other: Operand): Operand = this
            suspend operator fun get(index: Int): Int = index
            suspend infix fun combine(other: Operand): Operand = this
        }
        fun bad(a: Operand) { a + a; a[0]; a combine a }
        suspend fun good(a: Operand) { a + a; a[0]; a combine a }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0308" }.count == 3, "\(result.diagnostics)")
    }

    @Test
    func indexedWriteBackAndIterationCheckImplicitSuspendCalls() throws {
        let result = try diagnostics("""
        class Box {
            operator fun get(index: Int): Int = index
            suspend operator fun set(index: Int, value: Int) {}
        }
        class Cursor {
            operator fun hasNext(): Boolean = false
            suspend operator fun next(): Int = 1
        }
        class Values { operator fun iterator(): Cursor = Cursor() }
        fun bad(box: Box, values: Values) {
            box[0] += 1
            for (value in values) { println(value) }
        }
        suspend fun good(box: Box, values: Values) {
            box[0] += 1
            for (value in values) { println(value) }
        }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0308" }.count == 2, "\(result.diagnostics)")
    }

    @Test
    func destructuringChecksSuspendComponents() throws {
        let result = try diagnostics("""
        class Pairish { suspend operator fun component1() = 1 }
        class PairCursor {
            operator fun hasNext(): Boolean = false
            operator fun next(): Pairish = Pairish()
        }
        class PairValues { operator fun iterator(): PairCursor = PairCursor() }
        fun bad(value: Pairish, values: PairValues) {
            val (a) = value
            for ((b) in values) {}
        }
        suspend fun good(value: Pairish, values: PairValues) {
            val (a) = value
            for ((b) in values) {}
        }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0308" }.count == 2, "\(result.diagnostics)")
    }

    @Test
    func inlineLambdaInheritsOnlyAnAvailableSuspensionContext() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        inline fun direct(block: () -> Int) = block()
        inline fun escaped(noinline block: () -> Int) = block()
        inline fun crossed(crossinline block: () -> Int) = block()
        suspend fun good() { direct { sf() } }
        fun bad() { direct { sf() } }
        suspend fun escaping() {
            escaped { sf() }
            crossed { sf() }
            val stored = { direct { sf() } }
        }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0308" }.count == 4, "\(result.diagnostics)")
    }

    @Test
    func listAndIterableMapInheritSuspensionContexts() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.*
        inline fun direct(block: () -> Int): Int = block()
        suspend fun good(list: List<Deferred<Int>>, iterable: Iterable<Deferred<Int>>) {
            list.map { it.await() }
            iterable.map { it.await() }
        }
        fun blocking(list: List<Deferred<Int>>, iterable: Iterable<Deferred<Int>>) = runBlocking {
            list.map { direct { it.await() } }
            iterable.map { direct { it.await() } }
        }
        """)
        try runSema(ctx)
        let hasErrors = ctx.diagnostics.hasError
        #expect(!hasErrors, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var receiverNames: [String] = []
        for (id, binding) in sema.bindings.callBindings {
            guard let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  let symbol = sema.symbols.symbol(binding.chosenCallee),
                  ctx.interner.resolve(symbol.name) == "map",
                  let receiver = sema.symbols.functionSignature(for: symbol.id)?.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiver),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
            else { continue }
            receiverNames.append(ctx.interner.resolve(receiverSymbol.name))
            #expect(symbol.flags.contains(.inlineFunction))
        }
        #expect(receiverNames.filter { $0 == "List" }.count == 2)
        #expect(receiverNames.filter { $0 == "Iterable" }.count == 2)
    }

    @Test
    func listAndIterableMapKeepNonSuspendingLambdaBoundaries() throws {
        let result = try diagnostics("""
        import kotlinx.coroutines.*
        fun ordinary(block: () -> Int): Int = block()
        inline fun escaped(noinline block: () -> Int): Int = block()
        inline fun crossed(crossinline block: () -> Int): Int = block()
        fun outside(list: List<Deferred<Int>>, iterable: Iterable<Deferred<Int>>) {
            list.map { it.await() }
            iterable.map { it.await() }
        }
        fun blocking(list: List<Deferred<Int>>, iterable: Iterable<Deferred<Int>>) = runBlocking {
            list.map { ordinary { it.await() } }
            iterable.map { ordinary { it.await() } }
            list.map { escaped { it.await() } }
            iterable.map { escaped { it.await() } }
            list.map { crossed { it.await() } }
            iterable.map { crossed { it.await() } }
        }
        """, includeStdlib: true)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 8, "\(result.diagnostics)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0308" })
    }

    @Test
    func resultInlineLambdasInheritSuspension() throws {
        let result = try diagnostics("""
        class Ch {
            suspend fun flush() {}
            suspend fun flushAndClose() { runCatching { flush() } }
        }
        suspend fun sf(): Int = 7
        suspend fun good(result: Result<Int>, channel: Ch) {
            runCatching { channel.flushAndClose() }
            channel.runCatching { flush() }
            result.getOrElse { sf() }
            result.map { sf() }
            result.mapCatching { sf() }
            result.fold({ sf() }, { sf() })
            result.onSuccess { sf() }
            result.onFailure { sf() }
            result.recover { sf() }
            result.recoverCatching { sf() }
        }
        """, includeStdlib: true)
        #expect(!result.hasError, "\(result.diagnostics)")
    }

    @Test
    func resultInlineLambdasStillRequireSuspensionContext() throws {
        let result = try diagnostics("""
        suspend fun sf(): Int = 7
        fun bad(result: Result<Int>) {
            runCatching { sf() }
            result.runCatching { sf() }
            result.getOrElse { sf() }
            result.map { sf() }
            result.mapCatching { sf() }
            result.fold({ sf() }, { sf() })
            result.onSuccess { sf() }
            result.onFailure { sf() }
            result.recover { sf() }
            result.recoverCatching { sf() }
        }
        suspend fun stored() { val block = { runCatching { sf() } } }
        """, includeStdlib: true)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 12, "\(result.diagnostics)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0308" })
    }

}
