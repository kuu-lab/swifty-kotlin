import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine

private fun builder(block: suspend (String) -> Unit) {
    block.startCoroutine("OK", object : Continuation<Unit> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<Unit>) {
            result.getOrThrow()
            println("done")
        }
    })
}

fun main() {
    builder { value -> println(value) }
}
