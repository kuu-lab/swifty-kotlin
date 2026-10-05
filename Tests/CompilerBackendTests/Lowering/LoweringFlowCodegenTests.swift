#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private struct FlowTestFailure: Error, CustomStringConvertible {
    let description: String
}

@Suite
struct LoweringFlowCodegenTests {
    @Test
    func testBundledFlowOperatorsWinOverIntrinsicRewrite() throws {
        let source = """
        import kotlinx.coroutines.flow.*

        fun main() {
            runBlocking {
                val source = flow {
                    emit(1)
                    emit(2)
                }
                println(source.map { it * 2 }.toList())
                println(source.filter { it == 2 }.first())
                println(source.fold(0) { acc, value -> acc + value })
                println(source.reduce { acc, value -> acc + value })
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "FlowBundledPriority",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir, "KIR module not produced after lowering.")
            let allCallees = findAllKIRFunctions(in: module).flatMap { function in
                extractCallees(from: function.body, interner: ctx.interner)
            }

            // KSP-CAP-010: artifact imports inline the map/filter transforms,
            // while the non-inline terminal declarations retain concrete
            // mangled artifact callees.  The executable check below fixes the
            // observable semantics of the inlined transforms.
            #expect(containsKotlinCallee("toList", in: allCallees))
            #expect(containsKotlinCallee("first", in: allCallees))
            #expect(containsKotlinCallee("fold", in: allCallees))
            #expect(containsKotlinCallee("reduce", in: allCallees))
            #expect(allCallees.contains("kk_flow_create"))
            #expect(allCallees.contains("kk_flow_emit"))
            #expect(!allCallees.contains("__kk_flow_to_list"))
            #expect(!allCallees.contains("__kk_flow_first"))
            #expect(!allCallees.contains("__kk_flow_single"))
            #expect(!allCallees.contains("__kk_flow_fold"))
            #expect(!allCallees.contains("__kk_flow_reduce"))

            try assertFlowExecutableOutput(
                source: source,
                moduleName: "FlowBundledPriorityExecutable",
                expectedStdout: "[2, 4]\n2\n3\n3\n"
            )
        }
    }

    @Test
    func testImportedFlowCollectorImplicitEmitUsesInterfaceDispatch() throws {
        let source = """
        import kotlinx.coroutines.flow.*

        suspend fun FlowCollector<Int>.emitTwice(value: Int) {
            emit(value)
            emit(value * 10)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "ImportedFlowCollectorDispatch",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let instructions = findAllKIRFunctions(in: module).flatMap(\.body)
            let emitDispatches = instructions.compactMap { instruction -> KIRDispatchKind? in
                guard case let .virtualCall(_, callee, _, _, _, _, _, dispatch) = instruction,
                      isKotlinCallee(ctx.interner.resolve(callee), named: "emit")
                else { return nil }
                return dispatch
            }

            #expect(!emitDispatches.isEmpty)
            #expect(emitDispatches.allSatisfy {
                if case .itableDynamic = $0 { return true }
                return false
            })
            #expect(!instructions.contains {
                guard case let .call(_, callee, _, _, _, _, _, _) = $0 else { return false }
                return isKotlinCallee(ctx.interner.resolve(callee), named: "emit")
            })
        }
    }

    @Test(arguments: [false, true])
    func testOnEmptyPreservesEmitAndEmitAllOrder(useSourceStdlib: Bool) throws {
        let source = """
        import kotlinx.coroutines.flow.*
        import kotlinx.coroutines.runBlocking

        fun main() = runBlocking {
            println(emptyFlow<Int>().onEmpty {
                emit(7)
                emitAll(flowOf(8, 9))
            }.toList())
            println(emptyFlow<Int>().onEmpty {
                emitAll(flowOf(8, 9))
                emit(7)
            }.toList())
            println(emptyFlow<Int>().onEmpty {
                emit(7)
                emit(8)
                emitAll(flowOf(9))
            }.toList())
            val fallback = emptyFlow<Int>().onEmpty {
                emit(1)
                emitAll(emptyFlow<Int>())
                emit(2)
                emitAll(flowOf(3, 4))
                emit(5)
                emitAll(flowOf(6))
                emit(7)
            }
            println(fallback.toList())
            println(fallback.toList())
            println(emptyFlow<Int?>().onEmpty {
                emit(null)
                emitAll(flowOf(8, null))
                emit(9)
            }.toList())
            var calls = 0
            println(flowOf(10).onEmpty {
                calls += 1
                emit(7)
                emitAll(flowOf(8, 9))
            }.toList())
            println("calls:$calls")
            println(emptyFlow<Int>().onEmpty { emit(10) }.toList())
            println(flow<Int> {
                emit(7)
                emitAll(flowOf(8, 9))
            }.toList())
            try {
                emptyFlow<Int>().onEmpty {
                    emit(7)
                    emitAll(flow<Int> { throw IllegalArgumentException("nested") })
                    emit(8)
                }.collect { println("value:$it") }
            } catch (e: IllegalArgumentException) {
                println("failure:${e.message}")
            }
            Unit
        }
        """

        try assertFlowExecutableOutput(
            source: source,
            moduleName: "OnEmptyMixedEmissions",
            expectedStdout: """
            [7, 8, 9]
            [8, 9, 7]
            [7, 8, 9]
            [1, 2, 3, 4, 5, 6, 7]
            [1, 2, 3, 4, 5, 6, 7]
            [null, 8, null, 9]
            [10]
            calls:0
            [10]
            [7, 8, 9]
            value:7
            failure:nested

            """,
            useSourceStdlib: useSourceStdlib
        )
    }

    @Test(arguments: [2, 3, 4, 5])
    func testCapturedSuspendFunctionUsesInvokeABI(arity: Int) throws {
        let parameterTypes = Array(repeating: "Int", count: arity).joined(separator: ", ")
        let arguments = (["initial"] + Array(repeating: "value", count: arity - 1)).joined(separator: ", ")
        let source = """
        interface TestFlow

        suspend fun TestFlow.collect(collector: suspend (Int) -> Unit) {}

        suspend fun TestFlow.fold(
            initial: Int,
            operation: suspend (\(parameterTypes)) -> Int
        ): Int {
            collect { value -> operation(\(arguments)) }
            return initial
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FlowSuspendFunctionCapture", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir, "KIR module not produced after lowering.")
            let allCallees = findAllKIRFunctions(in: module).flatMap { function in
                extractCallees(from: function.body, interner: ctx.interner)
            }

            #expect(allCallees.contains("kk_suspend_function_invoke_\(arity)"))
            #expect(!allCallees.contains("operation"))
        }
    }

    @Test
    func testSuspendFunctionValuesInFlowCallbacksPreserveClosureEnvironment() throws {
        let source = """
        import kotlinx.coroutines.runBlocking
        import kotlinx.coroutines.flow.*

        suspend fun runFilter(pred: suspend (Int) -> Boolean) {
            flow { emit(1) }.collect { v ->
                try { pred(v) } catch (e: Throwable) { }
            }
            println("filter done")
        }

        suspend fun runMultiStatementCollector() {
            val scale = 2
            val op = { value: Int -> println(value * scale) }
            var n = 0
            flow { emit(1) }.collect { v -> op(v); n += 1 }
            println(n)
        }

        suspend fun <T> Flow<T>.onCompletionX(action: suspend (Throwable?) -> Unit): Flow<T> {
            return flow {
                this@onCompletionX.collect { emit(it) }
                action(null)
            }
        }

        fun main() {
            runBlocking {
                runFilter { println("predicate"); true }
                runMultiStatementCollector()
                flow { emit(1) }.onCompletionX { cause ->
                    if (cause == null) println("completion")
                }.collect { }
            }
        }
        """

        try assertFlowExecutableOutput(
            source: source,
            moduleName: "SuspendFunctionValueFlowEnvironment",
            expectedStdout: "predicate\nfilter done\n2\n1\ncompletion\n"
        )
    }

    @Test
    func testRunBlockingResolvesMaterializedSuspendCallable() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        fun runCollect(source: Flow<Int>, collector: suspend (Int) -> Unit) = runBlocking {
            source.collect(collector)
        }

        fun main() {
            runCollect(flowOf(1, 2, 3)) { delay(1); println(it) }
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "SuspendCallableLauncher",
            expectedStdout: "1\n2\n3\n"
        )
    }

    @Test(arguments: [1, 2, 3, 4])
    func testSuspendReceiverCallableAllowsLatestCancellation(arity: Int) throws {
        let parameterTypes = Array(repeating: "Int", count: arity).joined(separator: ", ")
        let arguments = Array(repeating: "value", count: arity).joined(separator: ", ")
        let parameterNames = (0..<arity).map { "value\($0)" }.joined(separator: ", ")
        let source = """
        import kotlinx.coroutines.*

        class Sink {
            val items = mutableListOf<Int>()
            fun append(value: Int) { items.add(value) }
        }

        suspend fun latest(transform: suspend Sink.(\(parameterTypes)) -> Unit): List<Int> {
            val sink = Sink()
            coroutineScope {
                var previous: Job? = null
                for (value in listOf(1, 2)) {
                    previous?.cancel()
                    previous?.join()
                    previous = launch(start = CoroutineStart.UNDISPATCHED) {
                        sink.transform(\(arguments))
                    }
                }
                previous?.join()
            }
            return sink.items
        }

        fun main() {
            runBlocking {
                println(latest { \(parameterNames) ->
                    append(value0)
                    delay(20)
                    append(value0 * 10)
                })
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SuspendReceiverCancellation", emit: .kirDump)
            try runToLowering(ctx)
            let module = try #require(ctx.kir)
            let functions = findAllKIRFunctions(in: module)
            let allCallees = functions.flatMap {
                extractCallees(from: $0.body, interner: ctx.interner)
            }
            #expect(allCallees.contains("kk_suspend_function_create"))
            #expect(allCallees.contains("kk_suspend_function_invoke_\(arity + 1)"))
            #expect(!allCallees.contains("transform"))
            for function in functions {
                for instruction in function.body {
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "kk_suspend_function_invoke_\(arity + 1)"
                    else { continue }
                    #expect(arguments.count == arity + 3)
                }
            }
        }
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "SuspendReceiverCancellationExecutable",
            expectedStdout: "[1, 2, 20]\n"
        )
    }

    @Test
    func testSuspendCallableValuesPreserveCapturesResultsAndExceptions() throws {
        let source = """
        import kotlinx.coroutines.*

        suspend fun zero(block: suspend () -> String): String = block()
        suspend fun one(block: suspend (Int) -> Int): Int = block(4)
        suspend fun two(block: suspend (Int, Int) -> Int): Int = block(4, 5)
        suspend fun three(block: suspend (Int, Int, Int) -> Int): Int = block(4, 5, 6)
        suspend fun four(block: suspend (Int, Int, Int, Int) -> Int): Int = block(4, 5, 6, 7)
        suspend fun five(block: suspend (Int, Int, Int, Int, Int) -> Int): Int = block(4, 5, 6, 7, 8)
        suspend fun receiver(block: suspend String.(Int) -> String): String = "value".block(6)
        suspend fun referenced(): String { delay(1); return "ref" }

        fun makeReceiver(prefix: String, suffix: String): suspend String.(Int) -> String = {
            delay(1)
            "$prefix$this:$it$suffix"
        }

        fun main() {
            runBlocking {
                val prefix = "capture"
                println(zero { delay(1); prefix })
                println(one { delay(1); it + 3 })
                println(two { a, b -> delay(1); a + b })
                println(three { a, b, c -> delay(1); a + b + c })
                println(four { a, b, c, d -> delay(1); a + b + c + d })
                println(five { a, b, c, d, e -> delay(1); a + b + c + d + e })
                println(receiver(makeReceiver("[", "]")))
                try { zero { delay(1); throw IllegalStateException("delayed") } }
                catch (e: IllegalStateException) { println(e.message) }
                try { zero { throw IllegalStateException("immediate") } }
                catch (e: IllegalStateException) { println(e.message) }
                println(zero(::referenced))
            }
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "SuspendCallableValuesExecutable",
            expectedStdout: "capture\n7\n9\n15\n22\n30\n[value:6]\ndelayed\nimmediate\nref\n"
        )
    }

    @Test
    func testSuspendBlocksPreserveCapturesInContextAndTimeout() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlin.time.Duration.Companion.milliseconds

        fun main() = runBlocking {
            val captured = 40
            println(withTimeout(1000) { delay(1); captured + 1 })
            println(withTimeoutOrNull(1000) { delay(1); captured + 2 })
            println(withContext(Dispatchers.Default) { delay(1); captured + 3 })
            println(withTimeout(1000.milliseconds) { delay(1.milliseconds); captured + 4 })
            println(withTimeoutOrNull(1000.milliseconds) { delay(1L); captured + 5 })
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "SuspendBlockCapturesExecutable",
            expectedStdout: "41\n42\n43\n44\n45\n"
        )
    }

    @Test
    func testSuspendPredicatesPreserveBooleanResultsAndCallerContext() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        suspend fun predicate(block: suspend (Int) -> Boolean): Boolean = block(2)

        fun main() = runBlocking {
            val limit = 30
            println(predicate { delay(1); it <= limit })
            println(predicate { delay(1); it > limit })
            println(flowOf(1, 2, 3, 4).map { it * 10 }
                .takeWhile { delay(1); it <= limit }.dropWhile { delay(1); it < 20 }.toList())
            println(coroutineContext.job.isActive)
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "SuspendBooleanResultsExecutable",
            expectedStdout: "true\nfalse\n[20, 30]\ntrue\n"
        )
    }

    @Test
    func testSuspendReceiverCallableUnwindsBeforeJoin() throws {
        let source = """
        import kotlinx.coroutines.*

        suspend fun invokeReceiver(block: suspend String.(Int) -> Unit) {
            "receiver".block(7)
        }

        fun main() {
            runBlocking {
                val job = launch(start = CoroutineStart.UNDISPATCHED) {
                    invokeReceiver {
                        try {
                            println(this)
                            delay(1000)
                            println("not cancelled")
                        } finally {
                            println("finally $it")
                        }
                    }
                }
                println("cancel")
                job.cancel()
                job.join()
                println("joined")
            }
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "SuspendReceiverUnwindExecutable",
            expectedStdout: "receiver\ncancel\nfinally 7\njoined\n"
        )
    }

    @Test
    func testSuspendProducerAndActorCallablesPreserveReceiverAndCaptures() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.channels.*

        fun main() = runBlocking {
            val base = 7
            val producer = produce {
                delay(1)
                send(base + 1)
                send(base * 10)
            }
            for (value in producer) println(value)
            val offset = 100
            val done = Channel<Int>(1)
            val worker = actor<Int> {
                for (value in channel) {
                    delay(1)
                    done.send(value + offset)
                }
            }
            worker.send(2)
            worker.close()
            println(done.receive())
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "SuspendProducerActorCallableExecutable",
            expectedStdout: "8\n70\n102\n"
        )
    }

    @Test
    func testBoxedRuntimeCallbacksExposeRawEntryPoints() throws {
        let source = """
        import kotlinx.io.*

        fun main() {
            val buffer = Buffer()
            val stream = buffer.asOutputStream()
            stream.write(65)
            stream.flush()
            stream.close()
            println(buffer.readByte())
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "BoxedRuntimeCallbackExecutable",
            expectedStdout: "65\n"
        )
    }

    @Test
    func testSuspendSupervisorScopeKeepsHandledFailuresIsolated() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            supervisorScope {
                val child = async {
                    delay(1)
                    throw IllegalStateException("child")
                }
                try {
                    child.await()
                } catch (error: IllegalStateException) {
                    println(error.message)
                }
            }
            delay(1)
            println("finished")
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "SuspendSupervisorScopeCallableExecutable",
            expectedStdout: "child\nfinished\n"
        )
    }

    @Test
    func testFailedBlockingCoroutineDoesNotCancelLaterLaunches() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() {
            try {
                runBlocking {
                    launch(start = CoroutineStart.UNDISPATCHED) {
                        delay(1)
                        throw IllegalStateException("child")
                    }
                }
            } catch (error: IllegalStateException) {
                println(error.message)
            }
            runBlocking {
                val child = launch(start = CoroutineStart.UNDISPATCHED) {
                    println("next")
                }
                child.join()
            }
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "FailedBlockingCoroutineCallableExecutable",
            expectedStdout: "child\nnext\n"
        )
    }

    @Test
    func testFlowLoweringRewritesFlowCallsToRuntimeABI() throws {
        let source = """
        fun main() {
            runBlocking {
                flow {
                    emit(1)
                    emit(2)
                }.transform {
                    emit(it * 2)
                    emit(it * 2 + 1)
                }
                    .collect { println(it) }
                val only = flow {
                    emit(7)
                }.single()
                println(only)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            // Exercise intrinsic lowering without bundled Flow declarations.
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "FlowLoweringRewrite", emit: .kirDump, includeStdlib: false
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir, "KIR module not produced after lowering.")
            let allCallees = findAllKIRFunctions(in: module).flatMap { extractCallees(from: $0.body, interner: ctx.interner) }

            #expect(allCallees.contains("kk_flow_create"))
            #expect(allCallees.contains("kk_flow_emit"))
            #expect(allCallees.contains("kk_flow_collect"))
            #expect(allCallees.contains("__kk_flow_single"))
            #expect(!allCallees.contains("flow"))
            #expect(!allCallees.contains("transform"))
            #expect(!allCallees.contains("collect"))
            #expect(!allCallees.contains("emit"))
            #expect(!allCallees.contains("single"))
        }
    }

    @Test
    func testCoroutineLoweringFlowCollectInjectsSuspendCollectorFunctionID() throws {
        let source = """
        fun main() {
            runBlocking {
                flow {
                    emit(1)
                }.collect {
                    delay(1)
                    println(it)
                }
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "FlowCollectSuspend", emit: .kirDump, includeStdlib: false
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir, "KIR module not produced after lowering.")
            let allFunctions = findAllKIRFunctions(in: module)
            let collectCallArgs = allFunctions
                .flatMap { $0.body }
                .compactMap { instruction -> [KIRExprID]? in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "kk_flow_collect"
                    else {
                        return nil
                    }
                    return arguments
                }
                .first

            guard let callArgs = collectCallArgs else {
                throw FlowTestFailure(description: "Expected kk_flow_collect call after lowering.")
            }
            // (flowHandle, collectorFnPtr, collectorEnvPtr, continuation/functionID).
            // The third slot (collectorEnvPtr) was added so collectors that
            // capture outer variables (e.g. `collect { capturedList.add(it) }`)
            // receive their closure environment instead of always being invoked
            // with a null environment pointer.
            #expect(callArgs.count == 4)

            guard let collectorExpr = module.arena.expr(callArgs[1]),
                  case let .symbolRef(collectorSymbol) = collectorExpr
            else {
                throw FlowTestFailure(description: "kk_flow_collect collector argument must be a symbol reference.")
            }

            let collectorFunction = allFunctions.first { function in
                function.symbol == collectorSymbol
            }
            let collectorName = collectorFunction.map { ctx.interner.resolve($0.name) } ?? ""
            #expect(
                collectorName.hasPrefix("kk_suspend_"),
                "Collector argument should be rewritten to suspend-lowered entry point."
            )

            guard let functionIDExpr = module.arena.expr(callArgs[3]),
                  case let .intLiteral(functionID) = functionIDExpr
            else {
                throw FlowTestFailure(description: "kk_flow_collect fourth argument must be a function ID literal.")
            }
            #expect(functionID != 0)
            #expect(functionID == Int64(collectorSymbol.rawValue))
        }
    }

    @Test
    func testFlowMapCollectExecutablePrintsExpectedOutput() throws {
        let source = """
        suspend fun runFlowCollectExecutable() {
            flow {
                emit(1)
                emit(2)
            }.map { it * 2 }
                .collect { println(it) }
        }

        fun main() {
            runBlocking { runFlowCollectExecutable() }
            return
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "FlowExecutable",
            expectedStdout: "2\n4\n"
        )
    }

    @Test
    func testNestedFlowCollectorsDoNotReenterTheInnerCollector() throws {
        let source = """
        fun main() {
            runBlocking {
                flow { emit(1); emit(2) }
                    .map { it * 2 }
                    .collect { println(it) }

                val values = flow { emit(1); emit(2); emit(3) }
                    .map { it * 10 }
                    .filter { it > 10 }
                    .toList()
                println(values)
            }
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "FlowNestedCollectorOwnership",
            expectedStdout: "2\n4\n[20, 30]\n"
        )
    }

    @Test
    func testFlowCollectTwiceLowersBothCollectCalls() throws {
        let source = """
        suspend fun runFlowCollectTwice() {
            val stream = flow {
                emit(1)
                emit(2)
            }.map { it * 2 }
            stream.collect { println(it) }
            stream.collect { println(it) }
        }

        fun main() {
            runBlocking(::runFlowCollectTwice)
            return
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "FlowColdExecutable", emit: .kirDump, includeStdlib: false
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir, "KIR module not produced after lowering.")
            let collectCalls = findAllKIRFunctions(in: module).compactMap { function -> Int? in
                let callees = extractCallees(from: function.body, interner: ctx.interner)
                let collectCount = callees.filter { $0 == "kk_flow_collect" }.count
                return collectCount == 0 ? nil : collectCount
            }.reduce(0, +)

            #expect(
                collectCalls == 2,
                "Lowering should preserve both collect calls for a reused cold flow."
            )
        }
    }

    @Test
    func testFlowLoweringInsertsFlowHandleReleaseCalls() throws {
        let source = """
        suspend fun runFlowOwnership() {
            val stream = flow {
                emit(1)
                emit(2)
            }
            val mapped = stream.map { it }
            stream.collect { println(it) }
            mapped.collect { println(it) }
        }

        fun main() {
            runBlocking(::runFlowOwnership)
            return
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "FlowOwnership", emit: .kirDump, includeStdlib: false
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir, "KIR module not produced after lowering.")
            let allCallees = findAllKIRFunctions(in: module).flatMap { extractCallees(from: $0.body, interner: ctx.interner) }

            #expect(allCallees.contains("__kk_flow_release"))
        }
    }

    // KSP-674: flowOf / emptyFlow / Iterable.asFlow are Kotlin source composed
    // from flow { } (kk_flow_create) + emit (kk_flow_emit); the dedicated
    // kk_flow_of / kk_flow_empty / kk_flow_as_flow bridges were removed. These
    // cases pin their end-to-end behavior, including the emitter-side capture of
    // an outer val inside an explicit flow { } builder.
    @Test
    func testFlowOfVarargExecutablePrintsExpectedOutput() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        suspend fun runFlowOf() {
            flowOf(1, 2, 3)
                .map { it * 10 }
                .filter { it > 10 }
                .collect { println(it) }
        }

        fun main() {
            runBlocking { runFlowOf() }
            return
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "FlowOfExecutable",
            expectedStdout: "20\n30\n"
        )
    }

    @Test
    func testEmptyFlowExecutableEmitsNothing() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        suspend fun runEmptyFlow() {
            emptyFlow<Int>()
                .collect { println(it) }
            println("done")
        }

        fun main() {
            runBlocking { runEmptyFlow() }
            return
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "EmptyFlowExecutable",
            expectedStdout: "done\n"
        )
    }

    @Test
    func testAsFlowCollectionExecutablePrintsExpectedOutput() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        suspend fun runAsFlow() {
            listOf(4, 5, 6)
                .asFlow()
                .map { it + 100 }
                .collect { println(it) }
        }

        fun main() {
            runBlocking { runAsFlow() }
            return
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "AsFlowExecutable",
            expectedStdout: "104\n105\n106\n"
        )
    }

    @Test
    func testFlowBuilderCapturesOuterValExecutable() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        suspend fun runCapturingFlow() {
            val base = 1000
            flow {
                for (i in 1..3) {
                    emit(base + i)
                }
            }.collect { println(it) }
        }

        fun main() {
            runBlocking { runCapturingFlow() }
            return
        }
        """
        try assertFlowExecutableOutput(
            source: source,
            moduleName: "FlowCaptureExecutable",
            expectedStdout: "1001\n1002\n1003\n"
        )
    }

    private func assertFlowExecutableOutput(
        source: String,
        moduleName: String,
        expectedStdout: String,
        useSourceStdlib: Bool = false
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let fileManager = FileManager.default
            let workDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: workDir) }
            let outputPath = workDir.appendingPathComponent("flow-executable").path

            let ctx = if useSourceStdlib {
                makeCompilationContext(
                    inputs: [path],
                    moduleName: moduleName,
                    emit: .executable,
                    outputPath: outputPath,
                    allowDefaultStdlibLibrary: false
                )
            } else {
                try makeArtifactCompilationContext(
                    inputs: [path],
                    moduleName: moduleName,
                    emit: .executable,
                    outputPath: outputPath
                )
            }
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let runResult = try CommandRunner.run(executable: outputPath, arguments: [])
            let normalizedStdout = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(runResult.exitCode == 0)
            #expect(normalizedStdout == expectedStdout)
        }
    }
}
#endif
