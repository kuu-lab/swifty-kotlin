import kotlinx.coroutines.*

fun main() {
    try {
        runBlocking {
            val cancelled = async { 1 }
            cancelled.cancel()
            try { cancelled.await() } catch (_: Throwable) {}
            try { cancelled.getCompleted() } catch (e: Throwable) { println(e.message) }
            println(cancelled.getCompletionExceptionOrNull()?.message)

            val failed = async { throw IllegalStateException("x") }
            try { failed.await() } catch (_: Throwable) {}
            try { failed.join() } catch (e: Throwable) { println(e.message) }
        }
    } catch (_: Throwable) {}
}
