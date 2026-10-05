import kotlinx.coroutines.*

fun main() {
    runBlocking {
        val lazyJob = launch(start = CoroutineStart.LAZY) { println("launch body") }
        println("launch before: ${lazyJob.isActive}")
        println("launch start: ${lazyJob.start()}")
        println("launch active: ${lazyJob.isActive}")
        val boxedStart: Any = lazyJob.start()
        println("launch boxed: $boxedStart")
        println("launch branch: ${if (lazyJob.start()) "started" else "already started"}")
        println("launch again: ${lazyJob.start()}")
        lazyJob.join()
        println("launch completed: ${lazyJob.start()}")

        val lazyTask = async(start = CoroutineStart.LAZY) { 42 }
        println("async before: ${lazyTask.isActive}")
        println("async start: ${lazyTask.start()}")
        println("async active: ${lazyTask.isActive}")
        println("async again: ${lazyTask.start()}")
        println("async result: ${lazyTask.await()}")
        println("async completed: ${lazyTask.start()}")

        val capture = "captured"
        val capturingJob = launch(start = CoroutineStart.LAZY) { println(capture) }
        println("capturing launch: ${capturingJob.start()}")
        capturingJob.join()
        val capturingTask = async(start = CoroutineStart.LAZY) { capture }
        val asJob: Job = capturingTask
        println("deferred as job: ${asJob.start()}")
        println("capturing async: ${capturingTask.start()}")
        println(capturingTask.await())

        val cancelledJob = launch(start = CoroutineStart.LAZY) { println("WRONG launch") }
        cancelledJob.cancel()
        println("cancelled launch: ${cancelledJob.start()}")
        cancelledJob.join()
        val cancelledTask = async(start = CoroutineStart.LAZY) { println("WRONG async"); 1 }
        cancelledTask.cancel()
        println("cancelled async: ${cancelledTask.start()}")

        val eagerJob = launch { }
        println("default launch: ${eagerJob.start()}")
        eagerJob.join()
        val eagerTask = async { 7 }
        println("default async: ${eagerTask.start()}")
        println(eagerTask.await())
        val immediate = async(start = CoroutineStart.UNDISPATCHED) { 8 }
        println("undispatched async: ${immediate.start()}")
        println(immediate.await())

        val standalone = Job()
        println("standalone: ${standalone.start()}")
        standalone.complete()
        println("completed standalone: ${standalone.start()}")
        val completable = CompletableDeferred<Int>()
        println("completable deferred: ${completable.start()}")
        completable.complete(9)
        println(completable.await())
        println("completed deferred: ${completable.start()}")
        println("noncancellable: ${NonCancellable.start()}")
    }
}
