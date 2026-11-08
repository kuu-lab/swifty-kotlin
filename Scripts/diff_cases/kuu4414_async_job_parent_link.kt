import kotlinx.coroutines.*

// KUU-4414: a Job passed as the async/launch context argument becomes the
// new coroutine's parent — job.parent and job.children reflect the link, and
// cancelling the parent cancels the child.

@OptIn(ExperimentalCoroutinesApi::class)
fun main() = runBlocking {
    val p = Job()
    val c = async(p) { 1 }
    println(c.parent === p)
    println(p.children.toList().size)
    println(p.children.contains(c))
    println(c.await())

    val p2 = Job()
    val j = launch(p2) { }
    println(j.parent === p2)
    println(p2.children.toList().size)
    j.join()

    // Implicit context still parents to the receiver scope's job.
    val scopeJob = coroutineContext.job
    val a = async { 7 }
    println(a.parent === scopeJob)
    println(scopeJob.children.contains(a))
    println(a.await())

    // Cancelling the explicit parent cancels the async child.
    val p3 = Job()
    val d = async(p3) { delay(5000); 9 }
    p3.cancel()
    try {
        d.await()
        println("await returned")
    } catch (e: CancellationException) {
        println("await cancelled")
    }
}
