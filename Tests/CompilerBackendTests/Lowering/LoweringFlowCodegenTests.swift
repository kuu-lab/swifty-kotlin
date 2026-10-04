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
    func testCapturedSuspendReceiverFunctionUsesThreeArgumentInvokeABI() throws {
        let source = """
        interface Collector

        suspend fun callPredicate(
            collector: Collector,
            predicate: suspend Collector.(Throwable, Long) -> Boolean
        ): Boolean = predicate(collector, IllegalStateException("retry"), 0L)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SuspendReceiverPredicate", emit: .kirDump)
            try runToLowering(ctx)
            let module = try #require(ctx.kir)
            let callees = findAllKIRFunctions(in: module).flatMap {
                extractCallees(from: $0.body, interner: ctx.interner)
            }
            #expect(callees.contains("kk_suspend_function_invoke_3"))
            #expect(!callees.contains("predicate"))
        }
    }

    @Test
    func testSuspendFunctionValuesInFlowCallbacksPreserveClosureEnvironment() throws {
        let source = """
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
    func testSuspendReceiverCallbackDispatchesImportedCollectorMember() throws {
        try assertFlowExecutableOutput(
            source: """
            import kotlinx.coroutines.flow.*

            class Printer : FlowCollector<Int> {
                override suspend fun emit(value: Int) { println(value) }
            }

            suspend fun send(collector: FlowCollector<Int>) { collector.emit(9) }

            suspend fun action(collector: FlowCollector<Int>, block: suspend FlowCollector<Int>.() -> Unit) {
                block(collector)
            }

            fun main() {
                runBlocking {
                    Printer().emit(8)
                    send(Printer())
                    val captured = 7
                    action(Printer()) { emit(captured) }
                }
            }
            """,
            moduleName: "SuspendReceiverCollectorDispatch",
            expectedStdout: "8\n9\n7\n"
        )
    }

    @Test
    func testDefaultFlowRetryUsesBundledSourceValidation() throws {
        try assertFlowExecutableOutput(
            source: """
            import kotlinx.coroutines.flow.*

            fun main() {
                try {
                    flowOf(1).retry(0)
                } catch (e: IllegalArgumentException) {
                    println("zero retry")
                }
                try {
                    flowOf(1).retry(-1)
                } catch (e: IllegalArgumentException) {
                    println("negative retry")
                }
            }
            """,
            moduleName: "DefaultFlowRetry",
            expectedStdout: "zero retry\nnegative retry\n"
        )
    }

    @Test
    func testSharedFlowOnSubscriptionRunsBeforeReplay() throws {
        try assertFlowExecutableOutput(
            source: """
            import kotlinx.coroutines.flow.*

            fun main() {
                runBlocking {
                    val shared = MutableSharedFlow<Int>(2)
                    shared.tryEmit(1)
                    shared.tryEmit(2)
                    val subscribed = shared.onSubscription { emit(0) }
                    println(subscribed.replayCache)
                    subscribed.collect { println(it) }
                    subscribed.collect { println(it) }
                }
            }
            """,
            moduleName: "SharedFlowOnSubscription",
            expectedStdout: "[1, 2]\n0\n1\n2\n0\n1\n2\n"
        )
    }

    @Test
    func testTransformLatestPreservesColdStreamingAndDownstreamFailures() throws {
        try assertFlowExecutableOutput(
            source: """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val transformed = flow<Int> {
                    println("start")
                    emit(1)
                    println("unreachable")
                    emit(2)
                }.transformLatest<Int, String> { value ->
                    emit("value=$value")
                    println("unreachable transform")
                }
                println("constructed")
                try {
                    transformed.collect { value ->
                        println(value)
                        throw IllegalStateException("downstream")
                    }
                } catch (e: IllegalStateException) {
                    println(e.message)
                }
                try {
                    transformed.collect { value ->
                        println(value)
                        throw IllegalStateException("downstream")
                    }
                } catch (e: IllegalStateException) {
                    println(e.message)
                }
            }
            """,
            moduleName: "TransformLatestStreaming",
            expectedStdout: "constructed\nstart\nvalue=1\ndownstream\nstart\nvalue=1\ndownstream\n"
        )
    }

    @Test
    func testFlowLoweringRewritesFlowCallsToRuntimeABI() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        fun main() {
            runBlocking {
                flow<Int> {
                    emit(1)
                    emit(2)
                }.transform<Int, Int> {
                    emit(it * 2)
                    emit(it * 2 + 1)
                }
                    .collect { println(it) }
                val only = flow<Int> {
                    emit(7)
                }.single()
                println(only)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FlowLoweringRewrite", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir, "KIR module not produced after lowering.")
            let allCallees = findAllKIRFunctions(in: module).filter { !$0.isInlineOnly }
                .flatMap { extractCallees(from: $0.body, interner: ctx.interner) }
            let sema = try #require(ctx.sema)

            #expect(allCallees.contains("kk_flow_create"))
            #expect(allCallees.contains("kk_flow_emit"))
            #expect(allCallees.contains("kk_flow_collect"))
            #expect(allCallees.contains("single"))
            #expect(allCallees.contains("transform"))
            #expect(!allCallees.contains("flow"))
            #expect(!allCallees.contains("collect"))
            #expect(!allCallees.contains("__kk_flow_single"))

            // Operators stay source-backed; only cold-flow primitives use runtime links.
            for function in findAllKIRFunctions(in: module) where !function.isInlineOnly {
                for instruction in function.body {
                    guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                          ["transform", "emit"].contains(ctx.interner.resolve(callee))
                    else { continue }
                    let chosenSymbol = try #require(symbol, "Unresolved Flow call remains after lowering")
                    #expect(sema.symbols.isSourceBackedSymbol(chosenSymbol))
                    let declaration = try #require(sema.symbols.symbol(chosenSymbol))
                    let fqName = declaration.fqName.map(ctx.interner.resolve).joined(separator: ".")
                    #expect(fqName.hasPrefix("kotlinx.coroutines.flow."))
                }
            }

            try assertFlowExecutableOutput(
                source: source,
                moduleName: "FlowLoweringRewriteExecutable",
                expectedStdout: "2\n3\n4\n5\n7\n"
            )
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
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FlowCollectSuspend", emit: .kirDump)
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
            runBlocking(::runFlowCollectExecutable)
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
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FlowColdExecutable", emit: .kirDump)
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
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FlowOwnership", emit: .kirDump)
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
            runBlocking(::runFlowOf)
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
            runBlocking(::runEmptyFlow)
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
            runBlocking(::runAsFlow)
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
            runBlocking(::runCapturingFlow)
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
        expectedStdout: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let fileManager = FileManager.default
            let workDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: workDir) }
            let outputPath = workDir.appendingPathComponent("flow-executable").path

            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputPath
            )
            try runToLowering(ctx)
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
