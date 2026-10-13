@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    @Test(arguments: [false, true])
    func testFlowTakeFirstAbort(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/flow_take_first_abort.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "FlowTakeFirstAbort",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
                Requested element count 0 should be positive
                Requested element count -1 should be positive
                start
                cleanup
                [1]
                start
                cleanup
                [1]
                start
                second
                cleanup
                [1, 2]
                start
                cleanup
                1
                start
                cleanup
                [1]
                start
                cleanup
                1
                [1, 2]
                []
                null
                empty
                start
                cleanup
                downstream
                upstream

                """)
        }
    }

    @Test
    func testFlowTerminalLogicThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        fun main() = runBlocking {
            println(emptyFlow<Int>().any { true })
            println(emptyFlow<Int>().all { false })
            println(emptyFlow<Int>().none { true })
            println(flowOf(1, 2, 3).any { it == 2 })
            println(flowOf(1, 2, 3).all { it > 0 })
            println(flowOf(1, 2, 3).none { it > 3 })
            var calls = 0
            println(flow<Int> {
                emit(1)
                emit(2)
                throw IllegalStateException("unreachable")
            }.any { value -> calls += 1; value == 2 })
            println(calls)
            println(flow<Int> {
                emit(1)
                throw IllegalStateException("unreachable")
            }.all { it > 1 })
            println(flow<Int?> {
                emit(null)
                throw IllegalStateException("unreachable")
            }.none { it == null })
            try {
                flowOf(1).any { throw IllegalArgumentException("predicate") }
            } catch (e: IllegalArgumentException) {
                println("predicate failure")
            }
            Unit
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "FlowTerminalLogic",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
                false
                true
                true
                true
                true
                true
                true
                2
                false
                false
                predicate failure

                """)
        }
    }

    @Test(arguments: [false, true])
    func testFlowAccumulatorsAndCollectorThroughSharedStdlibArtifact(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        fun runCollect(source: Flow<Int>, action: suspend (Int) -> Unit) = runBlocking {
            source.collect(action)
        }

        fun main() = runBlocking {
            val folded = flowOf(1, 2).runningFold("x") { acc, value -> acc + value }
            println(folded.toList())
            println(folded.toList())
            flowOf("a", "b").collectIndexed { index, value -> println("$index:$value") }
            var calls = 0
            val fallback = emptyFlow<Int>().onEmpty {
                calls += 1
                emit(7)
                emitAll(flowOf(8, 9))
            }
            println(calls)
            println(fallback.toList())
            println(fallback.toList())
            println(calls)
            val collector = object : FlowCollector<Int> {
                override suspend fun emit(value: Int) { println("collector:$value") }
            }
            collector.emitAll(flowOf(10, 11))
            runCollect(flowOf(12, 13)) { value -> println("forwarded:$value") }
            try {
                emptyFlow<Int>().onEmpty { throw IllegalArgumentException("action") }.toList()
            } catch (e: IllegalArgumentException) {
                println("action failure")
            }
            Unit
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "FlowAccumulatorsAndCollector",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
                [x, x1, x12]
                [x, x1, x12]
                0:a
                1:b
                0
                [7, 8, 9]
                [7, 8, 9]
                2
                collector:10
                collector:11
                forwarded:12
                forwarded:13
                action failure

                """)
        }
    }

    @Test
    func testFlowCollectSuspendConversionThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlinx.coroutines.flow.*
        import kotlinx.coroutines.runBlocking
        fun runCollect(source: Flow<Int>, action: (Int) -> Unit) = runBlocking {
            source.collect(action)
        }
        fun runFailure(action: (Int) -> Unit) = runBlocking {
            try { flowOf(1).collect(action) }
            catch (e: IllegalArgumentException) { println(e.message) }
        }
        fun main() {
            runCollect(flowOf(12, 13)) { println(it) }
            var total = 10
            val action: (Int) -> Unit = { total += it }
            runCollect(flowOf(2, 3), action)
            runCollect(flowOf(4), action)
            println(total)
            val failure: (Int) -> Unit = { throw IllegalArgumentException("converted") }
            runFailure(failure)
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath], moduleName: "FlowCollectSuspendConversion",
                emit: .executable, outputPath: outputBase,
                includeStdlib: false, stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "12\n13\n19\nconverted\n")
        }
    }
}
