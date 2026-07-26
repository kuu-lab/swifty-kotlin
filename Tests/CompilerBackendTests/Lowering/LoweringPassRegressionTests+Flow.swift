@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

final class LoweringFlowCodegenTests: XCTestCase {
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
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FlowLoweringRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            var allCallees: [String] = []
            for function in findAllKIRFunctions(in: module) {
                allCallees.append(contentsOf: extractCallees(from: function.body, interner: ctx.interner))
            }

            XCTAssertTrue(allCallees.contains("kk_flow_create"))
            XCTAssertTrue(allCallees.contains("kk_flow_emit"))
            XCTAssertTrue(allCallees.contains("kk_flow_collect"))
            XCTAssertTrue(allCallees.contains("kk_flow_single"))
            XCTAssertFalse(allCallees.contains("flow"))
            XCTAssertFalse(allCallees.contains("transform"))
            XCTAssertFalse(allCallees.contains("collect"))
            XCTAssertFalse(allCallees.contains("emit"))
            XCTAssertFalse(allCallees.contains("single"))
        }
    }

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
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            var collectCallArgs: [KIRExprID]?
            for function in findAllKIRFunctions(in: module) {
                for instruction in function.body {
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "kk_flow_collect"
                    else {
                        continue
                    }
                    collectCallArgs = arguments
                    break
                }
                if collectCallArgs != nil {
                    break
                }
            }

            let callArgs = try XCTUnwrap(collectCallArgs, "Expected kk_flow_collect call after lowering.")
            // (flowHandle, collectorFnPtr, collectorEnvPtr, continuation/functionID).
            // The third slot (collectorEnvPtr) was added so collectors that
            // capture outer variables (e.g. `collect { capturedList.add(it) }`)
            // receive their closure environment instead of always being invoked
            // with a null environment pointer.
            XCTAssertEqual(callArgs.count, 4)

            guard let collectorExpr = module.arena.expr(callArgs[1]),
                  case let .symbolRef(collectorSymbol) = collectorExpr
            else {
                XCTFail("kk_flow_collect collector argument must be a symbol reference.")
                return
            }

            let collectorFunction = findAllKIRFunctions(in: module).first { function in
                function.symbol == collectorSymbol
            }
            let collectorName = collectorFunction.map { ctx.interner.resolve($0.name) } ?? ""
            XCTAssertTrue(
                collectorName.hasPrefix("kk_suspend_"),
                "Collector argument should be rewritten to suspend-lowered entry point."
            )

            guard let functionIDExpr = module.arena.expr(callArgs[3]),
                  case let .intLiteral(functionID) = functionIDExpr
            else {
                XCTFail("kk_flow_collect fourth argument must be a function ID literal.")
                return
            }
            XCTAssertNotEqual(functionID, 0)
            XCTAssertEqual(functionID, Int64(collectorSymbol.rawValue))
        }
    }

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
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let collectCalls = findAllKIRFunctions(in: module).compactMap { function -> Int? in
                let callees = extractCallees(from: function.body, interner: ctx.interner)
                let collectCount = callees.filter { $0 == "kk_flow_collect" }.count
                return collectCount == 0 ? nil : collectCount
            }.reduce(0, +)

            XCTAssertEqual(collectCalls, 2, "Lowering should preserve both collect calls for a reused cold flow.")
        }
    }

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
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            var allCallees: [String] = []
            for function in findAllKIRFunctions(in: module) {
                allCallees.append(contentsOf: extractCallees(from: function.body, interner: ctx.interner))
            }

            XCTAssertTrue(allCallees.contains("kk_flow_release"))
        }
    }

    // KSP-674: flowOf / emptyFlow / Iterable.asFlow are Kotlin source composed
    // from flow { } (kk_flow_create) + emit (kk_flow_emit); the dedicated
    // kk_flow_of / kk_flow_empty / kk_flow_as_flow bridges were removed. These
    // cases pin their end-to-end behavior, including the emitter-side capture of
    // an outer val inside an explicit flow { } builder.
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
        expectedStdout: String,
        irFlags: [String] = []
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let fileManager = FileManager.default
            let workDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: workDir) }
            let outputPath = workDir.appendingPathComponent("flow-executable").path

            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputPath,
                irFlags: irFlags
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let runResult = try CommandRunner.run(executable: outputPath, arguments: [])
            let normalizedStdout = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(runResult.exitCode, 0)
            XCTAssertEqual(normalizedStdout, expectedStdout)
        }
    }
}
