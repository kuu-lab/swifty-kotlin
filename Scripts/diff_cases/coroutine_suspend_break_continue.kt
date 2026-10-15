import kotlin.coroutines.*
import kotlin.coroutines.intrinsics.*

private class Probe {
    var log = ""
    var count = 0

    suspend fun <T> pass(value: T): T =
        suspendCoroutineUninterceptedOrReturn { continuation ->
            continuation.resume(value)
            COROUTINE_SUSPENDED
        }
}

private class EmptyCompletion : Continuation<Unit> {
    override val context: CoroutineContext = EmptyCoroutineContext
    override fun resumeWith(result: Result<Unit>) {}
}

private fun evaluate(body: suspend Probe.() -> Unit): String {
    val probe = Probe()
    body.startCoroutine(probe, EmptyCompletion())
    return probe.log
}

fun main() {
    println(evaluate {
        outer@ for (x in listOf("O", "K")) {
            log += pass(x)
            for (y in listOf("Q", "W")) {
                log += pass(y)
                if (y == "W") break@outer
            }
        }
        log += "."
    })
    println(evaluate {
        try {
            outer@ for (x in listOf(1)) {
                try {
                    log += pass("a")
                    for (y in listOf(1)) {
                        try {
                            log += pass("b")
                            break@outer
                        } finally {
                            log += "i"
                        }
                    }
                } finally {
                    log += "o"
                }
            }
        } finally {
            log += "f"
        }
        log += "."
    })
    println(evaluate {
        outer@ do {
            log += "o"
            count++
            inner@ do {
                log += pass(count.toString())
                if (count == 1) break@inner
                break@outer
            } while (false)
            log += "x"
        } while (true)
    })
    println(evaluate {
        for (x in listOf("A", "skip", "B")) {
            if (x == "skip") {
                log += "s"
                continue
            }
            log += pass(x)
            if (x == "A") {
                log += "a"
                continue
            }
            log += "b"
        }
        log += "."
    })
}
