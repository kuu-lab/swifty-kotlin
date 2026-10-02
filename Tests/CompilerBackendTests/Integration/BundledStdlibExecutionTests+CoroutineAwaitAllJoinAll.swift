#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    /// Collection-receiver `awaitAll()` / `joinAll()` regression. Before these
    /// were added to the bundled kotlinx.coroutines source, only the vararg
    /// `awaitAll(vararg deferreds: Deferred)` existed: `list.awaitAll()`
    /// failed with `KSWIFTK-SEMA-0003` (overload resolution reached the vararg
    /// form and could not make the list fit) and `list.joinAll()` with
    /// `KSWIFTK-SEMA-0024`, so the idiomatic "async/launch a list, then
    /// await/join the list" pattern did not compile.
    ///
    /// The third block pins fail-fast: awaiting sequentially must let the
    /// element's exception escape rather than swallowing it.
    ///
    /// The trailing `println("done")` is load-bearing, not decoration (the
    /// same reason every coroutine case in Scripts/diff_cases ends with one):
    /// `coroutineScope` returns `Any` here, so without it the `try`/`catch`
    /// would be the block's value and `main` would return `Any` instead of
    /// `Unit`. kswiftc then uses that value as the process exit code -- for a
    /// boxed value the low pointer byte, which varies per run. That is a
    /// separate pre-existing defect (it reproduces with plain `a.await()` and
    /// no `awaitAll` at all), so this test deliberately keeps `main`
    /// `Unit`-valued rather than depending on it.
    @Test
    func testCollectionAwaitAllAndJoinAllResolveAndRun() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*

            suspend fun boom(): Int {
                throw RuntimeException("boom")
            }

            fun main() = runBlocking {
                val ds = listOf(async { 1 }, async { 2 }, async { 3 })
                println(ds.awaitAll().sum())

                var counter = 0
                val js = listOf(launch { counter += 1 }, launch { counter += 10 })
                js.joinAll()
                println(counter)

                try {
                    coroutineScope {
                        listOf(async { 10 }, async { boom() }).awaitAll()
                    }
                } catch (e: Throwable) {
                    println(e.message)
                }
                println("done")
            }
            """,
            expectedOutput: "6\n11\nboom\ndone\n"
        )
    }
}
#endif
