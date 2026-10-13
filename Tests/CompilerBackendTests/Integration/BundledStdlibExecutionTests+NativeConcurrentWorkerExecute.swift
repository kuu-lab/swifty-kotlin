import Testing

extension BundledStdlibExecutionTests {
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

    // Before this migration, `Worker.execute` was a synthetic member whose
    // symbol carried `externalLinkName == "kk_worker_execute"` directly, so
    // `materializeSourceBackedFunctionValueArguments`'s `kk_fn_`-prefix guard
    // (CallLowerer+ClosureAdapters.swift) returned early and never touched its
    // lambda arguments. Migrating `execute` to a genuine Kotlin-source
    // function (this PR) means `chosenCallee` at that call site is now
    // `execute` itself, which has no `externalLinkName` of its own — the
    // guard's `if let` fails to bind, so it falls through and boxes both
    // lambda arguments via `kk_function_create_0`/`_1` before they ever reach
    // the later, `kk_worker_execute`-specific expansion in
    // CallLowerer+MemberCallEmission.swift. That expansion resolves the now-
    // boxed `producer` correctly via `makeClosureThunkExpandedArguments`, but
    // `job` goes through `makeCollectionHOFExpandedArguments`, whose
    // no-compile-time-info fallback forwards the boxed argument as-is with a
    // literal `0` closureRaw instead of unwrapping it. The native
    // kk_worker_execute bridge must unwrap it itself (see
    // resolveFunctionValuePair in RuntimeFunctionTypes.swift) instead of
    // treating it as a raw function pointer — otherwise the worker thread
    // jumps into the wrapped handle's object header as if it were code and
    // crashes. Any future migration that source-backs a function CallLowerer
    // otherwise renames straight to a `kk_`-prefixed bridge can hit the same
    // trap.

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
