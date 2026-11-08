import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlin.coroutines.EmptyCoroutineContext

// KUU-4361: CoroutineExceptionHandler is an interface — `by`-delegation,
// `object :` implementations, the factory function, and context lookup must
// all resolve like upstream kotlinx.coroutines.

class Collector : AbstractCoroutineContextElement(CoroutineExceptionHandler.Key), CoroutineExceptionHandler {
    var seen = 0
    override fun handleException(context: CoroutineContext, exception: Throwable) {
        seen += 1
        println("handled: ${exception.message}")
    }
}

class Delegating(val inner: CoroutineExceptionHandler) : CoroutineExceptionHandler by inner

fun main() {
    val collector = Collector()
    val delegating = Delegating(collector)
    delegating.handleException(EmptyCoroutineContext, RuntimeException("delegated"))
    println("collector.seen=${collector.seen}")

    val factory = CoroutineExceptionHandler { _, ex -> println("factory saw ${ex.message}") }
    factory.handleException(EmptyCoroutineContext, RuntimeException("boom"))

    val direct = object : AbstractCoroutineContextElement(CoroutineExceptionHandler.Key), CoroutineExceptionHandler {
        override fun handleException(context: CoroutineContext, exception: Throwable) {
            println("direct object saw ${exception.message}")
        }
    }
    direct.handleException(EmptyCoroutineContext, IllegalStateException("obj"))
    println("key ok: ${direct.key == CoroutineExceptionHandler.Key}")
    println("lookup: ${(direct + EmptyCoroutineContext)[CoroutineExceptionHandler] != null}")
}
