// KUU-3403: reified class literals survive chained suspend inline calls through crossinline lambdas.
import kotlin.coroutines.*
import kotlin.coroutines.intrinsics.*

private class Controller {
    var result = ""
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

private inline fun <reified T : Any> nameOf(): String = T::class.simpleName!!

private inline fun nonSuspend(crossinline block: () -> String): String = block()
private inline fun <reified T : Any> nonSuspend(): String = nonSuspend { T::class.simpleName!! }

private inline suspend fun si(value: String): String =
    suspendCoroutineUninterceptedOrReturn { continuation ->
        continuation.resume(value)
        COROUTINE_SUSPENDED
    }

private inline suspend fun si(crossinline block: () -> String): String = si(block())
private inline suspend fun <reified T : Any> si(): String = si({ T::class.simpleName!! })

private class OK2

fun main() {
    println(nameOf<OK2>())
    println(nonSuspend<OK2>())
    println(builder { result = si<OK2>() })
}
