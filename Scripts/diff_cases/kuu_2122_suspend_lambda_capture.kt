import kotlin.coroutines.*
import kotlin.coroutines.intrinsics.*

private val completion = object : Continuation<Unit> {
    override val context: CoroutineContext = EmptyCoroutineContext
    override fun resumeWith(result: Result<Unit>) { result.getOrThrow() }
}

private fun builder(block: suspend () -> Unit) {
    block.startCoroutine(completion)
}

private inline fun inlineContextBlock(block: () -> Unit) {
    block()
}

private suspend fun useInlinedContext(): Boolean {
    inlineContextBlock { return coroutineContext === EmptyCoroutineContext }
    return false
}

private suspend fun suspendHere(): String {
    var value = "fail1"
    suspendCoroutineUninterceptedOrReturn<Unit> { continuation ->
        value = "OK"
        continuation.resume(Unit)
        COROUTINE_SUSPENDED
    }
    return value
}

private class First {
    val o = "O"

    inner class Second {
        val k = "K"

        private suspend fun suspendHereAndContinue(): String =
            suspendCoroutineUninterceptedOrReturn { continuation ->
                continuation.resume(this@First.o + this.k)
                COROUTINE_SUSPENDED
            }

        suspend fun getResult(): String = suspendHereAndContinue()
    }
}

private class Controller {
    suspend fun suspendHere(block: () -> String = { "DEF" }): String =
        suspendCoroutineUninterceptedOrReturn { continuation ->
            continuation.resume(block())
            COROUTINE_SUSPENDED
        }

    suspend fun getDef(): String = "DEF2"

    suspend fun suspendHere2(block: suspend () -> String = { getDef() }): String {
        val result = block()
        return suspendCoroutineUninterceptedOrReturn { continuation ->
            continuation.resume(result)
            COROUTINE_SUSPENDED
        }
    }
}

private fun builder1(block: suspend Controller.() -> Unit) {
    block.startCoroutine(Controller(), completion)
}

private interface Consumer { fun consume(s: String) }

private inline fun crossInlineBuilderConsumer(crossinline block: (String) -> Unit) = object : Consumer {
    override fun consume(s: String) {
        block(s)
    }
}

private inline fun inlineBuilder(block: () -> Consumer) = block()

private fun builderConsumer(block: suspend () -> Consumer): Consumer {
    var result: Consumer? = null
    block.startCoroutine(object : Continuation<Consumer> {
        override fun resumeWith(value: Result<Consumer>) {
            result = value.getOrThrow()
        }

        override val context: CoroutineContext = EmptyCoroutineContext
    })
    return result!!
}

private class Container {
    var y = "FAIL 0"

    val consumer0 = crossInlineBuilderConsumer { s -> y = s }
    val consumer1 = crossInlineBuilderConsumer { s -> builder { y = s } }
    val consumer2 = inlineBuilder {
        object : Consumer {
            override fun consume(s: String) {
                builder { y = s }
            }
        }
    }
    val consumer3 = inlineBuilder {
        builderConsumer {
            object : Consumer {
                override fun consume(s: String) {
                    y = s
                }
            }
        }
    }
    val consumer4 = crossInlineBuilderConsumer { _ ->
        object : Consumer {
            override fun consume(s: String) {
                builder { y = s }
            }
        }
    }
    val consumer5 = crossInlineBuilderConsumer { _ ->
        builderConsumer {
            object : Consumer {
                override fun consume(s: String) {
                    y = s
                }
            }
        }
    }
    val consumer6 = crossInlineBuilderConsumer { s ->
        val consumer = object : Consumer {
            override fun consume(s1: String) {
                builder { y = s1 }
            }
        }
        consumer.consume(s)
    }
    val consumer7 = crossInlineBuilderConsumer { s ->
        val consumer = builderConsumer {
            object : Consumer {
                override fun consume(s1: String) {
                    y = s1
                }
            }
        }
        consumer.consume(s)
    }
}

private fun runCrossInline(): String {
    val container = Container()
    container.consumer0.consume("OK")
    if (container.y != "OK") return container.y
    container.y = "FAIL 1"
    container.consumer1.consume("OK")
    if (container.y != "OK") return container.y
    container.y = "FAIL 2"
    container.consumer2.consume("OK")
    if (container.y != "OK") return container.y
    container.y = "FAIL 3"
    container.consumer3.consume("OK")
    if (container.y != "OK") return container.y
    container.y = "OK"
    container.consumer4.consume("FAIL 4")
    if (container.y != "OK") return container.y
    container.consumer5.consume("FAIL 5")
    if (container.y != "OK") return container.y
    container.y = "FAIL 6"
    container.consumer6.consume("OK")
    if (container.y != "OK") return container.y
    container.y = "FAIL 7"
    container.consumer7.consume("OK")
    if (container.y != "OK") return container.y
    return "OK"
}

fun main() {
    var result = "fail2"
    builder { result = suspendHere() }
    println("capturedVar:$result")

    var outerThis = "Nothing was called"
    builder {
        val first = First()
        val second = first.Second()
        outerThis = second.getResult()
    }
    println("outerThis:$outerThis")

    var defaultResult = "FAIL 1"
    builder1 {
        if (suspendHere() != "DEF") {
            defaultResult = "FAIL"
            return@builder1
        }
        if (suspendHere2() != "DEF2") {
            defaultResult = "FAIL"
            return@builder1
        }
        defaultResult = suspendHere { "OK" }
    }
    println("defaultParameter:$defaultResult")

    println("crossInline:${runCrossInline()}")

    var inlineContext = "FAIL 1"
    builder {
        if (useInlinedContext()) inlineContext = "OK"
    }
    println("coroutineContextInlineReturn:$inlineContext")

    inlineContext = "FAIL 2"
    builder {
        inlineContextBlock {
            inlineContext = if (coroutineContext === EmptyCoroutineContext) "OK" else "FAIL 3"
        }
    }
    println("coroutineContextInlineRead:$inlineContext")
}
