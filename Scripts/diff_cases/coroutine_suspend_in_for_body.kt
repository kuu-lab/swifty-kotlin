import kotlin.coroutines.*
import kotlin.coroutines.intrinsics.*

private class Controller {
    var result = ""

    suspend fun <T> suspendWithResult(value: T): T = suspendCoroutineUninterceptedOrReturn { continuation ->
        continuation.resume(value)
        COROUTINE_SUSPENDED
    }
}

private object EmptyContinuation : Continuation<Unit> {
    override val context: CoroutineContext = EmptyCoroutineContext
    override fun resumeWith(result: Result<Unit>) {}
}

private fun builder(block: suspend Controller.() -> Unit): String {
    val controller = Controller()
    block.startCoroutine(controller, EmptyContinuation)
    return controller.result
}

fun main() {
    val statement = builder {
        for (value in listOf("O", "K")) {
            result += suspendWithResult(value)
        }
        result += "."
    }
    val continued = builder {
        for (value in listOf("O", "$", "K")) {
            if (value == "$") continue
            result += suspendWithResult(value)
        }
        result += "."
    }
    val stepped = builder {
        for (value: Long in 20L..30L step 5L) {
            listOf("#").forEach {
                result += it + suspendWithResult(value).toString()
            }
        }
        result += "."
    }

    println("$statement|$continued|$stepped")
}
