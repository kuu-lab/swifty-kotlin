import kotlin.coroutines.*

private val completion = object : Continuation<Unit> {
    override val context: CoroutineContext = EmptyCoroutineContext
    override fun resumeWith(result: Result<Unit>) { result.getOrThrow() }
}

private inline fun inlinedLambda(block: () -> Unit) {
    block()
}

private suspend fun useInlined(): Boolean {
    inlinedLambda { return coroutineContext === EmptyCoroutineContext }
    return false
}

private fun builder(block: suspend () -> Unit) {
    block.startCoroutine(completion)
}

fun main() {
    var result = "DIRECT FAIL"
    builder {
        if (coroutineContext === EmptyCoroutineContext) result = "DIRECT OK"
    }
    println(result)

    result = "FAIL 1"
    builder {
        if (useInlined()) result = "OK"
    }
    println(result)

    result = "FAIL 2"
    builder {
        inlinedLambda {
            result = if (coroutineContext === EmptyCoroutineContext) "OK" else "FAIL 3"
        }
    }
    println(result)
}
