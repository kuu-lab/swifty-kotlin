// NOTE: Requires kotlinx-coroutines on classpath.
// Regression coverage for the `await()` fast path: when the child `async` has
// already failed before `await()` is called, the failure must still propagate
// (previously the completed-task branch returned the zero result and swallowed
// the exception, making coroutine_scope_wrapper_regression fail intermittently).
import kotlinx.coroutines.*

suspend fun boom(): Int {
    throw RuntimeException("child-fail")
}

fun main() = runBlocking {
    try {
        coroutineScope {
            val a = async { boom() }
            delay(200)
            a.await()
        }
    } catch (e: Throwable) {
        println("caught-completed: ${e.message}")
    }

    try {
        coroutineScope {
            val a = async { boom() }
            a.await()
        }
    } catch (e: Throwable) {
        println("caught-pending: ${e.message}")
    }

    val ok = coroutineScope {
        val a = async { 20 }
        delay(200)
        a.await() + 22
    }
    println(ok)
    println("done")
}
