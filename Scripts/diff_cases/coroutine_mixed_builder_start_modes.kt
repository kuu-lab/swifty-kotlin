import kotlinx.coroutines.*

fun main() {
    runBlocking {
        val job = launch(start = CoroutineStart.LAZY) {
            println("lazy launch first")
            yield()
            println("lazy launch second")
        }
        val task = async {
            println("default async first")
            yield()
            println("default async second")
            10
        }
        println("before lazy join")
        job.join()
        println(task.await())
    }

    runBlocking {
        launch {
            println("default launch first")
            yield()
            println("default launch second")
        }
        val task = async(start = CoroutineStart.LAZY) {
            println("lazy async first")
            yield()
            println("lazy async second")
            20
        }
        println("before lazy await")
        println(task.await())
    }

    runBlocking {
        launch {
            println("queued launch first")
            yield()
            println("queued launch second")
        }
        val task = async(start = CoroutineStart.UNDISPATCHED) {
            println("inline async first")
            yield()
            println("inline async second")
            30
        }
        println("after inline async")
        yield()
        println(task.await())
    }

    runBlocking {
        launch(start = CoroutineStart.UNDISPATCHED) {
            println("inline launch first")
            yield()
            println("inline launch second")
        }
        async {
            println("queued async first")
            yield()
            println("queued async second")
        }
        yield()
        println("after inline launch")
    }

    runBlocking {
        launch(start = CoroutineStart.ATOMIC) {
            println("atomic launch first")
            yield()
            println("atomic launch second")
        }
        async(start = CoroutineStart.ATOMIC) {
            println("atomic async first")
            yield()
            println("atomic async second")
        }
        yield()
        println("atomic parent")
    }

    runBlocking {
        val job = launch { println("cancelled launch must not run") }
        job.cancel()
        launch { println("surviving launch") }
        async { println("surviving async") }
        yield()
        job.join()
        println("cancelled launch joined")
    }

    runBlocking {
        val scope = CoroutineScope(Dispatchers.Default)
        val task = scope.async {
            yield()
            40
        }
        val job = launch(Dispatchers.IO) { yield() }
        job.join()
        println("explicit dispatcher result: ${task.await()}")
        scope.cancel()
    }
}
