@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    /// KSP-675: `SharedFlow`/`MutableSharedFlow` are bundled Kotlin source, so
    /// their members must keep working when the consumer only sees them through
    /// a prebuilt stdlib artifact. Reading `replayCache` through the interface
    /// needs the imported nominal's generic shape plus its itable property
    /// getter slot; calling `collect` needs the imported member to stay
    /// virtually dispatched and to keep the Kotlin (not runtime-bridge)
    /// argument shape, whose failure modes were an undefined reference to
    /// `replayCache`, a silently skipped `collect`, and a segfault in the HOF
    /// adapter.
    @Test
    func testSharedFlowThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlinx.coroutines.runBlocking
        import kotlinx.coroutines.flow.MutableSharedFlow
        import kotlinx.coroutines.flow.SharedFlow
        import kotlinx.coroutines.flow.flowOf
        import kotlinx.coroutines.flow.shareIn

        fun main() = runBlocking {
            val shared = MutableSharedFlow<Int>(2)
            println(shared.tryEmit(1))
            shared.emit(2)
            shared.emit(3)
            println(shared.replayCache)
            shared.take(2).collect { value -> println("class=$value") }

            val view: SharedFlow<Int> = shared
            println(view.replayCache)
            view.take(2).collect { value -> println("iface=$value") }

            println(flowOf(4, 5, 6).shareIn(2).replayCache)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
                true
                [2, 3]
                class=2
                class=3
                [2, 3]
                iface=2
                iface=3
                [5, 6]

                """)
        }
    }

    @Test
    func testFlowSharingSurfaceThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Scripts/diff_cases/kotlinx_coroutines_flow_share_surface.kt"
        ), encoding: .utf8)
        try expectFlowSharingOutput(source, artifactPath: artifactPath, expected: """
            collector=1
            collector=2
            7
            [-1, -2, 7]
            true
            true
            true
            -1
            []
            []
            invalid-stop
            invalid-replay

            """)
    }

    @Test(arguments: [false, true])
    func testFlowSharingSnapshotsAndLegacyOverloadsThroughSharedStdlibArtifact(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        class SubscriptionCounts : StateFlow<Int> {
            override val value: Int get() = 0
            override val replayCache: List<Int> get() = listOf(0)
            override suspend fun collect(collector: suspend (Int) -> Unit) {
                collector(0)
                collector(1)
                collector(2)
                collector(0)
            }
        }

        fun main() = runBlocking {
            val scope = CoroutineScope(Job())
            val counts = SubscriptionCounts()
            println(SharingStarted.Lazily.command(counts).toList() == listOf(SharingCommand.START))
            println(SharingStarted.WhileSubscribed().command(counts).toList() ==
                listOf(SharingCommand.START, SharingCommand.STOP))
            println(SharingStarted.WhileSubscribed(0L, 0L).command(counts).toList() ==
                listOf(SharingCommand.START, SharingCommand.STOP_AND_RESET_REPLAY_CACHE))
            val state = flowOf(2, 3).stateIn(scope, SharingStarted.Lazily, -1)
            println(state.value)
            state.take(1).collect { println("state=$it") }
            println(state.value)
            val shared = flowOf(4, 5).shareIn(scope, SharingStarted.Lazily, 2)
            println(shared.replayCache)
            shared.take(2).collect { println("shared=$it") }
            println(shared.replayCache)
            val reset = flowOf(6).stateIn(scope, SharingStarted.WhileSubscribed(0L, 0L), -2)
            reset.take(1).collect { println("reset=$it") }
            println(reset.value)
            reset.take(1).collect { println("restart=$it") }
            println(reset.value)
            val eager = flowOf(7).shareIn(scope, SharingStarted.Eagerly, 1)
            eager.take(1).collect { println("eager=$it") }
            println(eager.replayCache)
            val mutable = MutableStateFlow(0)
            val collector: FlowCollector<Int> = mutable
            flowOf(10, 11).collect(collector)
            println(mutable.value)
            println(flowOf(8, 9).stateIn(0).value)
            println(flowOf(12, 13, 14).shareIn(2).replayCache)
            scope.cancel()
        }
        """
        try expectFlowSharingOutput(source, artifactPath: artifactPath, expected: """
            true
            true
            true
            -1
            state=3
            3
            []
            shared=4
            shared=5
            [4, 5]
            reset=6
            -2
            restart=6
            -2
            eager=7
            [7]
            11
            9
            [13, 14]

            """)
    }

    @Test(arguments: [false, true])
    func testLazyFlowSharingCapturedLauncher(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        try expectFlowSharingOutput("""
            import kotlinx.coroutines.*
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val shared = flowOf(1, 2).shareIn(this, SharingStarted.Lazily, 2)
                println(shared.take(2).toList())
            }
            """, artifactPath: artifactPath, expected: "[1, 2]\n")
    }

    @Test(arguments: [false, true])
    func testCoroutineLauncherPreservesGenericReceiverAndLocalCapture(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        try expectFlowSharingOutput("""
            import kotlinx.coroutines.*

            fun accept(scope: CoroutineScope) { println("scope") }

            class Launcher<T>(val scope: CoroutineScope, var value: T) {
                fun read(): T = value
                fun start(): Job {
                    val local = 2
                    return scope.launch {
                        accept(this)
                        println(read())
                        value = read()
                        println(value)
                        println(local)
                    }
                }
            }

            fun main() = runBlocking {
                Launcher(this, 41).start().join()
            }
            """, artifactPath: artifactPath, expected: "scope\n41\n41\n2\n")
    }

    @Test(arguments: [false, true])
    func testProduceActorLiteralBlocks(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Scripts/diff_cases/kotlinx_coroutines_produce_actor_basic.kt"
        ), encoding: .utf8)
        try expectFlowSharingOutput(source, artifactPath: artifactPath,
                                    expected: "produced total: 60\ncaptured: 2\nlooped last: 9\nactor got: 107\nactor got: 108\ndone\n")
    }

    @Test(arguments: [false, true])
    func testProduceActorStoredBlocks(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Scripts/diff_cases/kuu1127_produce_actor_stored_blocks.kt"
        ), encoding: .utf8)
        try expectFlowSharingOutput(source, artifactPath: artifactPath,
                                    expected: "uncaptured: 3\nsingle: 6\ncaptured: 9\nforwarded: 15\nactor: 33\n")
    }

    private func expectFlowSharingOutput(_ source: String, artifactPath: String?, expected: String) throws {
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath], moduleName: "TestModule", emit: .executable,
                outputPath: outputBase, includeStdlib: artifactPath == nil, stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected)
        }
    }

    /// KSP-676: `StateFlow`/`MutableStateFlow`/`Flow.stateIn` are bundled Kotlin source, so
    /// they must keep working when the consumer only sees them through a prebuilt stdlib artifact.
    /// This covers `value`, `tryEmit`, `emit`, `replayCache`, `collect`, and the `stateIn` extension
    /// lowered to `kk_flow_collect` on an explicit local receiver.
    @Test
    func testStateFlowThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlinx.coroutines.runBlocking
        import kotlinx.coroutines.flow.*

        fun main() = runBlocking {
            val state = MutableStateFlow(10)
            println(state.value)

            state.tryEmit(20)
            println(state.value)

            state.emit(30)
            println(state.value)

            val view: StateFlow<Int> = state
            println(view.value)
            println(view.replayCache)

            val initial = 0
            val stateFromFlow = flowOf(1, 2, 3).stateIn(initial)
            println(stateFromFlow.value)

            val shared = flowOf(4, 5, 6).shareIn(1)
            println(shared.replayCache)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
                10
                20
                30
                30
                [30]
                3
                [6]

                """)
        }
    }

    @Test(arguments: [false, true])
    func testMutableFlowHierarchy(fromSource: Bool) throws {
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/kuu1296_mutable_flow_hierarchy.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "MutableFlowHierarchy",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
                true
                false
                10
                true
                12
                [12]
                0
                true
                [12]
                true
                true
                13
                state reset unsupported
                0
                true
                [21]
                []
                false
                false
                null

                """)
        }
    }

    @Test(arguments: [false, true])
    func testMutableSharedFlowSubscriptionCountTracksLaunchedCollectors(fromSource: Bool) throws {
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/kuu1465_mutable_shared_flow_subscription_count.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "MutableSharedFlowSubscriptionCount",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
                1
                0

                """)
        }
    }

    /// KUU-1599: hot flows must keep their collectors registered while they
    /// wait for updates, deliver emissions to every subscriber, and release
    /// each subscription on completion or cancellation.
    @Test(arguments: [false, true])
    func testHotFlowEmissionsReachLiveCollectors(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        fun main() = runBlocking {
            suspend fun awaitCondition(label: String, condition: () -> Boolean) {
                var remaining = 1000
                while (remaining > 0 && !condition()) {
                    delay(1)
                    remaining -= 1
                }
                check(condition()) { "Timed out waiting for $label" }
            }

            suspend fun awaitJob(label: String, job: Job) {
                awaitCondition(label) { job.isCompleted }
                job.join()
            }

            val shared = MutableSharedFlow<Int>()
            val sharedCount = shared.subscriptionCount
            val sharedValues = mutableListOf<Int>()
            val sharedJob = launch {
                shared.take(3).collect { sharedValues.add(it) }
            }
            awaitCondition("shared subscription") { sharedCount.value == 1 }
            println("sharedCount=${sharedCount.value}")
            shared.emit(1)
            delay(5)
            shared.emit(2)
            delay(5)
            shared.emit(3)
            awaitJob("shared take completion", sharedJob)
            println("shared=${sharedValues}")
            println("sharedCountAfter=${sharedCount.value}")

            val state = MutableStateFlow(0)
            val stateCount = state.subscriptionCount
            val stateValues = mutableListOf<Int>()
            val stateJob = launch {
                state.take(3).collect { stateValues.add(it) }
            }
            awaitCondition("state subscription") { stateCount.value == 1 }
            println("stateCount=${stateCount.value}")
            state.value = 1
            delay(5)
            state.value = 1
            delay(5)
            state.value = 2
            awaitJob("state take completion", stateJob)
            println("state=${stateValues}")
            println("stateCountAfter=${stateCount.value}")

            val multiple = MutableSharedFlow<Int>()
            val multipleCount = multiple.subscriptionCount
            val firstValues = mutableListOf<Int>()
            val secondValues = mutableListOf<Int>()
            val firstJob = launch {
                multiple.collect { firstValues.add(it) }
            }
            val secondJob = launch {
                multiple.collect { secondValues.add(it) }
            }
            awaitCondition("both shared subscriptions") { multipleCount.value == 2 }
            println("multipleCount=${multipleCount.value}")
            multiple.emit(10)
            delay(5)
            multiple.emit(20)
            awaitCondition("both shared collectors receive both values") {
                firstValues.size == 2 && secondValues.size == 2
            }
            firstJob.cancelAndJoin()
            secondJob.cancelAndJoin()
            println("multipleFirst=${firstValues}")
            println("multipleSecond=${secondValues}")
            println("multipleCountAfter=${multipleCount.value}")

            val operators = MutableSharedFlow<Int>()
            val operatorValues = mutableListOf<Int>()
            val operatorJob = launch {
                operators.drop(1).take(2).collect { operatorValues.add(it) }
            }
            awaitCondition("operator subscription") { operators.subscriptionCount.value == 1 }
            operators.emit(4)
            delay(5)
            operators.emit(5)
            delay(5)
            operators.emit(6)
            awaitJob("drop/take completion", operatorJob)
            println("dropTake=${operatorValues}")

            val latest = MutableSharedFlow<Int>()
            val latestCount = latest.subscriptionCount
            val latestValues = mutableListOf<Int>()
            val latestFinished = CompletableDeferred<Int>()
            val latestJob = launch {
                latest.collectLatest { value ->
                    if (value == 1) delay(80)
                    latestValues.add(value)
                    if (value == 3) latestFinished.complete(value)
                }
            }
            awaitCondition("collectLatest subscription") { latestCount.value == 1 }
            println("latestCount=${latestCount.value}")
            latest.emit(1)
            delay(10)
            latest.emit(2)
            delay(100)
            latest.emit(3)
            awaitCondition("collectLatest third value") { latestFinished.isCompleted }
            println("latestFinished=${latestFinished.await()}")
            latestJob.cancelAndJoin()
            println("latest=${latestValues}")
            println("latestCountAfter=${latestCount.value}")

            val lazySubscriptionCount = MutableStateFlow(0)
            val lazyCommands = mutableListOf<SharingCommand>()
            val lazyCommandJob = launch {
                SharingStarted.Lazily.command(lazySubscriptionCount).take(1)
                    .collect { lazyCommands.add(it) }
            }
            awaitCondition("lazy command subscription") {
                lazySubscriptionCount.subscriptionCount.value == 1
            }
            lazySubscriptionCount.value = 1
            awaitJob("lazy command start", lazyCommandJob)
            println("lazyCommands=${lazyCommands}")
            println("lazyCommandCountAfter=${lazySubscriptionCount.subscriptionCount.value}")

            val whileSubscribedCount = MutableStateFlow(0)
            val whileSubscribedCommands = mutableListOf<SharingCommand>()
            val whileSubscribedJob = launch {
                SharingStarted.WhileSubscribed().command(whileSubscribedCount).take(2)
                    .collect { whileSubscribedCommands.add(it) }
            }
            awaitCondition("while-subscribed command subscription") {
                whileSubscribedCount.subscriptionCount.value == 1
            }
            whileSubscribedCount.value = 1
            awaitCondition("while-subscribed start command") {
                whileSubscribedCommands.size == 1
            }
            whileSubscribedCount.value = 0
            awaitJob("while-subscribed stop command", whileSubscribedJob)
            println("whileSubscribedCommands=${whileSubscribedCommands}")
            println("whileSubscribedCommandCountAfter=${whileSubscribedCount.subscriptionCount.value}")

            val sharingScope = CoroutineScope(Job())
            val defaultReplay = flowOf(1, 2, 3).shareIn(sharingScope, SharingStarted.Eagerly)
            val explicitReplay = flowOf(1, 2, 3).shareIn(sharingScope, SharingStarted.Eagerly, replay = 3)
            awaitCondition("explicit replay cache") { explicitReplay.replayCache.size == 3 }
            println("defaultReplay=${defaultReplay.replayCache}")
            println("explicitReplay=${explicitReplay.replayCache}")
            sharingScope.cancel()
        }
        """
        try expectFlowSharingOutput(source, artifactPath: artifactPath, expected: """
            sharedCount=1
            shared=[1, 2, 3]
            sharedCountAfter=0
            stateCount=1
            state=[0, 1, 2]
            stateCountAfter=0
            multipleCount=2
            multipleFirst=[10, 20]
            multipleSecond=[10, 20]
            multipleCountAfter=0
            dropTake=[5, 6]
            latestCount=1
            latestFinished=3
            latest=[2, 3]
            latestCountAfter=0
            lazyCommands=[START]
            lazyCommandCountAfter=0
            whileSubscribedCommands=[START, STOP]
            whileSubscribedCommandCountAfter=0
            defaultReplay=[]
            explicitReplay=[1, 2, 3]\n
            """)
    }

    @Test(arguments: [false, true])
    func testSnapshotFlowAPIs(fromSource: Bool) throws {
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let source = """
        import kotlin.coroutines.EmptyCoroutineContext
        import kotlinx.coroutines.runBlocking
        import kotlinx.coroutines.flow.*

        fun main() = runBlocking {
            val shared = MutableSharedFlow<Int>(2)
            shared.emit(1)
            shared.emit(2)
            val count = shared.subscriptionCount
            val view = shared.asSharedFlow()
            println(count.value)
            view.take(2).collect { value ->
                println("shared=$value/count=${count.value}")
                if (value == 1) {
                    shared.resetReplayCache()
                    shared.tryEmit(3)
                }
            }
            println(count.value)
            println(view.replayCache)
            try {
                view.collect { throw IllegalStateException("stop") }
            } catch (e: IllegalStateException) {
                println("exception/count=${count.value}")
            }
            shared.take(1).collect {
                shared.take(1).collect { println("nested=${count.value}") }
                println("outer=${count.value}")
            }
            println(count.value)
            println(view.buffer(0) === view)
            println(view.flowOn(EmptyCoroutineContext) === view)
            println(view.cancellable() === view)
            println(view.conflate() === view)
            try {
                view.buffer(-3)
            } catch (e: IllegalArgumentException) {
                println("invalid buffer")
            }
            val state = MutableStateFlow(5)
            val stateCount = state.subscriptionCount
            val stateView = state.asStateFlow()
            stateView.collect { value ->
                state.value = 6
                println("state=$value/count=${stateCount.value}")
            }
            println(stateCount.value)
            println(stateView.value)
            println(stateView.replayCache)
            println(stateView.distinctUntilChanged() === stateView)
            println(state.asSharedFlow().replayCache)
            state.setValue(7)
            println(stateView.value)
            try {
                state.collect { throw IllegalStateException("stop") }
            } catch (e: IllegalStateException) {
                println("state exception/count=${stateCount.value}")
            }
            stateCount.collect { println("count snapshot=$it") }
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
                0
                shared=1/count=1
                shared=2/count=1
                0
                [3]
                exception/count=0
                nested=2
                outer=1
                0
                true
                true
                true
                true
                invalid buffer
                state=5/count=1
                0
                6
                [6]
                true
                [6]
                7
                state exception/count=0
                count snapshot=0

                """)
        }
    }
}
