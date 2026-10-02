import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testCoroutineNominalsPreserveJobBridges(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                val job: CompletableJob = Job()
                println(job.isActive)
                println(job.complete())
                job.awaitCompletion()
                println(job.isCompleted)
                println(job.complete())
                val failed: CompletableJob = Job()
                println(failed.completeExceptionally(Exception("failed")))
                println(failed.isCancelled)
                val supervisor: CompletableJob = SupervisorJob()
                supervisor.cancel()
                println(supervisor.isCancelled)
                val deferred = async { 42 }
                println(deferred.await())
                val child: Job = deferred
                child.join()
                println(child.isCompleted)
                val local = JobImpl()
                println(local.isActive)
                println(local.complete())
                println(local.isCompleted)
                val handle: ChildHandle = NonDisposableHandle
                println(handle.parent == null)
                println(handle.childCancelled(Exception("child")))
                handle.dispose()
            }
            """,
            expectedOutput: "true\ntrue\ntrue\nfalse\ntrue\ntrue\ntrue\n42\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
