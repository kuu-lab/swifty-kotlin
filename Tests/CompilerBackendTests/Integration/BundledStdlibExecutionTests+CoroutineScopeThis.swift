import Testing

// KUU-1416: `this` inside bare `launch {}`/`async {}` (and the other coroutine
// builder lambdas whose bodies sema-check against an ambient CoroutineScope
// implicit receiver) used to lower to `.unit` — `this is CoroutineScope`
// returned false, `as?` returned null, and passing `this` into a member
// CoroutineScope call crashed on an invalid scope handle. These tests pin the
// fixed behaviour end-to-end: `this` materializes the runtime's current scope
// and carries the CoroutineScope nominal type tag.
extension BundledStdlibExecutionTests {
    /// Minimal reproduction A from the issue: type check and safe cast on
    /// `this` inside a bare `launch {}`, plus a member property read through it.
    @Test
    func testLaunchThisIsCoroutineScopeAndSupportsMemberAccess() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            fun main() = runBlocking {
                launch {
                    println(this is CoroutineScope)
                    val s: CoroutineScope? = this as? CoroutineScope
                    println(s != null)
                    println(this.isActive)
                }.join()
            }
            """,
            expectedOutput: "true\ntrue\ntrue\n"
        )
    }

    /// `this` must stay bound to the ambient scope across a suspension point,
    /// inside a nested receiverless lambda (captured receiver), and in every
    /// builder shape (`runBlocking`/`launch`/`async`/`coroutineScope`/
    /// `supervisorScope`/`withContext`).
    @Test
    func testCoroutineBuilderThisAcrossSuspensionAndNestedLambdas() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            fun main() = runBlocking {
                println(this is CoroutineScope)
                launch {
                    delay(1)
                    println(this is CoroutineScope)
                    listOf(1).forEach {
                        println(this is CoroutineScope)
                    }
                }.join()
                println(async { this is CoroutineScope }.await())
                coroutineScope {
                    println(this is CoroutineScope)
                }
                supervisorScope {
                    println(this is CoroutineScope)
                }
                withContext(Dispatchers.Default) {
                    println(this is CoroutineScope)
                }
                println("done")
            }
            """,
            expectedOutput: "true\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ndone\n"
        )
    }

    /// Minimal reproduction B from the issue: passing the builder's `this` to
    /// a `CoroutineScope` member call (`scope.launch`) used to hit
    /// `kk_coroutine_scope_launch received invalid scope handle` /
    /// `Virtual dispatch failed` because the receiver was `.unit`/a raw
    /// untyped handle.
    @Test
    func testCoroutineScopeMemberLaunchFromThisDoesNotCrash() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.flow.*

            fun <T> Flow<T>.myLaunchIn(scope: CoroutineScope): Job {
                val source = this
                return scope.launch { source.collect { println(it) } }
            }

            fun main() = runBlocking {
                flowOf(7).myLaunchIn(this).join()
            }
            """,
            expectedOutput: "7\n"
        )
    }
}
