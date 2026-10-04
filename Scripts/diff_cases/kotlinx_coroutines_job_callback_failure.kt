import kotlinx.coroutines.*

fun main() = runBlocking {
    supervisorScope {
        val deferred = async(start = CoroutineStart.LAZY) {
            throw IllegalStateException("failed")
        }
        var calls = 0
        deferred.invokeOnCompletion { cause ->
            calls++
            println(cause?.message)
        }
        try {
            deferred.await()
        } catch (failure: IllegalStateException) {
            println(failure.message)
        }
        println(calls)
        println(deferred.parent == null)
    }
}
