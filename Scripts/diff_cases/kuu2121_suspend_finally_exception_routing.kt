import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine

// KUU-2121: a suspend exception thrown from a nested finally must reach the enclosing catch.
suspend fun noOp() {}

suspend fun throwFromFinally() {
    throw IllegalStateException("finally")
}

suspend fun guarded(): String {
    return try {
        try {
            noOp()
            "body"
        } finally {
            throwFromFinally()
        }
    } catch (exception: IllegalStateException) {
        "caught:${exception.message}"
    }
}

fun main() {
    var output = "pending"
    val block: suspend () -> String = ::guarded
    block.startCoroutine(object : Continuation<String> {
        override val context = EmptyCoroutineContext
        override fun resumeWith(result: Result<String>) {
            output = result.fold({ it }, { "uncaught:${it.message}" })
        }
    })
    println(output)
}
