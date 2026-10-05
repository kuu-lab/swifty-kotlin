import kotlinx.coroutines.*

fun main() = runBlocking {
    val regular = launch {
        try {
            coroutineScope { awaitCancellation() }
        } finally {
            println("coroutineScope cleanup")
        }
    }
    yield()
    regular.cancelAndJoin()
    println("coroutineScope cancelled=${regular.isCancelled} completed=${regular.isCompleted}")

    val supervisor = launch {
        try {
            supervisorScope { awaitCancellation() }
        } finally {
            println("supervisorScope cleanup")
        }
    }
    yield()
    supervisor.cancelAndJoin()
    println("supervisorScope cancelled=${supervisor.isCancelled} completed=${supervisor.isCompleted}")

    val nested = launch {
        try {
            coroutineScope { supervisorScope { awaitCancellation() } }
        } finally {
            println("nested cleanup")
        }
    }
    yield()
    nested.cancelAndJoin()
    println("nested cancelled=${nested.isCancelled} completed=${nested.isCompleted}")

    val selfCancelled = launch {
        try {
            supervisorScope {
                currentCoroutineContext().cancel()
                awaitCancellation()
            }
        } finally {
            println("scope job cleanup")
        }
    }
    selfCancelled.join()
    println("scope job cancelled=${selfCancelled.isCancelled} completed=${selfCancelled.isCompleted}")
}
