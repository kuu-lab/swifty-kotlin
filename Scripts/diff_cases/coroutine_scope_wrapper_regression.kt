// NOTE: Requires kotlinx-coroutines on classpath.
// Regression coverage for KSP-679: coroutineScope/supervisorScope are bundled
// Kotlin wrappers delegating to (c) scope primitives. Exercises suspend
// function-value invocation (0- and 1-arg), local catch inside a suspend HOF,
// and that a caught coroutineScope child failure does not leak into a later
// supervisorScope.
import kotlinx.coroutines.*

suspend fun boom(): Int {
    throw RuntimeException("child-fail")
}

suspend fun probe0(block: suspend () -> Int): Int {
    try {
        return block()
    } catch (e: Throwable) {
        return -1
    }
}

suspend fun probe1(x: Int, block: suspend (Int) -> Int): Int {
    return block(x) + 1
}

fun main() = runBlocking {
    println(probe0 { 41 })
    println(probe0 { throw RuntimeException("boom") })
    println(probe1(10) { it * 2 })

    val ok = coroutineScope {
        val a = async { 20 }
        val b = async { 22 }
        a.await() + b.await()
    }
    println(ok)

    try {
        coroutineScope {
            val a = async { boom() }
            a.await()
        }
    } catch (e: Throwable) {
        println("caught: ${e.message}")
    }

    val supervised = supervisorScope {
        val g = async { 7 }
        g.await()
    }
    println(supervised)
    println("done")
}
