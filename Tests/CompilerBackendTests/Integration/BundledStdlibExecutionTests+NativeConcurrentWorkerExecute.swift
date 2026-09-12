import Testing

extension BundledStdlibExecutionTests {
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
}
