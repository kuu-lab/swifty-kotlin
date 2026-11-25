@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testFutureConsumeSourceStdlibO0() throws {
        try checkFutureConsumeCallbacks(optLevel: .O0)
    }

    @Test
    func testFutureConsumeSourceStdlibO2() throws {
        try checkFutureConsumeCallbacks(optLevel: .O2)
    }

    private func checkFutureConsumeCallbacks(optLevel: OptimizationLevel) throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
            import kotlin.native.concurrent.Future
            import kotlin.native.concurrent.TransferMode
            import kotlin.native.concurrent.withWorker

            fun consumeWith(future: Future<Int>, code: (Int) -> Int): Int = future.consume(code)

            fun main() {
                withWorker {
                    println(execute(TransferMode.SAFE, { 40 }) { value: Int -> value + 1 }
                        .consume { value: Int -> value + 1 })
                    val offset = 7
                    val code: (Int) -> Int = { it + offset }
                    println(consumeWith(execute(TransferMode.SAFE, { 35 }) { value: Int -> value }, code))
                    try {
                        execute(TransferMode.SAFE, { 1 }) { value: Int -> value }.consume<Int> {
                            throw IllegalStateException("callback")
                        }
                    } catch (e: IllegalStateException) {
                        println(e.message)
                    }
                }
            }
            """,
            expectedOutput: "42\n42\ncallback\n",
            allowDefaultStdlibLibrary: false,
            optLevel: optLevel
        )
    }

    @Test(arguments: [false, true])
    func testWithWorkerWithoutQueuedJobsCompletesNormally(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            @file:Suppress("DEPRECATION_ERROR")
            @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
            import kotlin.native.concurrent.withWorker

            fun main() {
                withWorker { println("inside") }
                println("after")
            }
            """,
            expectedOutput: "inside\nafter\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testWorkerReceiverFunctionValueAndExecuteThreadContract(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            @file:Suppress("DEPRECATION_ERROR")
            @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
            import kotlin.native.concurrent.Worker
            import kotlin.native.concurrent.Future
            import kotlin.native.concurrent.TransferMode
            import kotlin.native.concurrent.withWorker

            fun Worker.compute(): Int = execute<Int, Int>(TransferMode.SAFE, { 35 }) { it + 7 }.result

            fun main() {
                val caller = Worker.current.id
                val seed = 35
                var producedOnCaller = false
                fun staticJob(input: Int): Int = input + 7
                val block: Worker.() -> Int = {
                    val future: Future<Int> = execute<Int, Int>(TransferMode.SAFE, {
                        producedOnCaller = Worker.current.id == caller
                        seed
                    }) { input -> input + 7 }
                    val onWorker: Future<Boolean> = this.execute<Int, Boolean>(
                        TransferMode.SAFE, { caller }
                    ) { input -> Worker.current.id != input }
                    println(onWorker.result)
                    println(compute())
                    println(this.execute(TransferMode.SAFE, { seed }, ::staticJob).result)
                    println(execute(TransferMode.SAFE, { seed }) { staticJob(it) }.result)
                    future.result
                }
                println(withWorker("receiver-value", true, block))
                println(producedOnCaller)
            }
            """,
            expectedOutput: "true\n42\n42\n42\n42\ntrue\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test
    func testWorkerExecuteJobRunsWithoutWithWorker() throws {
        try compileAndRunKotlin(
            """
            @file:Suppress("DEPRECATION_ERROR")
            @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

            import kotlin.native.concurrent.TransferMode
            import kotlin.native.concurrent.Worker

            fun main() {
                val worker = Worker.start()
                val future = worker.execute(TransferMode.SAFE, { 35 }) { input -> input + 7 }
                println(future.result)
                worker.requestTermination(true)
            }
            """,
            expectedOutput: "42\n"
        )
    }

    @Test
    func testWorkerExecuteAfterRunsTrailingLambdaOperation() throws {
        try compileAndRunKotlin(
            """
            @file:Suppress("DEPRECATION_ERROR")
            @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

            import kotlin.native.concurrent.Worker

            fun main() {
                val worker = Worker.start()
                worker.executeAfter(0L) { println("ran") }
                worker.requestTermination(true)
            }
            """,
            expectedOutput: "ran\n"
        )
    }
}
