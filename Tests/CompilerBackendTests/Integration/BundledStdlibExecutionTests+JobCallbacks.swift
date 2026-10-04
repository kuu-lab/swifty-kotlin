#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testJobCallbacksAndHierarchyResolveAndRun() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                val root = coroutineContext.job
                val job = launch(start = CoroutineStart.LAZY) {}
                println(job.parent === root)
                println(root.children.toList().size)
                var calls = ""
                job.invokeOnCompletion { cause -> calls += if (cause == null) "A" else "X" }
                val disposed = job.invokeOnCompletion { calls += "X" }
                job.invokeOnCompletion(true, false) { calls += "B" }
                disposed.dispose()
                job.join()
                println(calls)
                println(job.parent == null)
                job.invokeOnCompletion(false, false) { println("unexpected") }.dispose()
                println(job.invokeOnCompletion { println(it == null) }.toString())
                val child = launch(start = CoroutineStart.LAZY) {}
                root.cancelChildren()
                child.join()
                println(child.isCancelled)
                println(root.isActive)
                println(root.children.toList().size)
                val deferred = async(start = CoroutineStart.LAZY) { 42 }
                println(deferred.parent === root)
                deferred.invokeOnCompletion { println(it == null) }
                println(deferred.await())
                println(deferred.parent == null)
            }
            """,
            expectedOutput: "true\n1\nAB\ntrue\ntrue\nNonDisposableHandle\ntrue\ntrue\n0\ntrue\ntrue\n42\ntrue\n"
        )
    }
}
#endif
