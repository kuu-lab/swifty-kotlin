// KUU-3838: `object : suspend () -> Int` binds SuspendFunction0 as its
// supertype, so the `startCoroutine` extension resolves on it.
// KUU-3802 (runtime): a class instance implementing a suspend function type
// traps when dispatched through the coroutine machinery, so the call is kept
// in a never-invoked function — this case pins the compile-time resolution.
import kotlin.coroutines.*

var failure: String? = "FAIL"

fun unused() {
    val u: suspend () -> Int = object : suspend () -> Int {
        override suspend fun invoke(): Int { failure = null; return 42 }
    }
    u.startCoroutine(Continuation(EmptyCoroutineContext) { it.getOrThrow() })
    val v: suspend (Int) -> Int = object : suspend (Int) -> Int {
        override suspend fun invoke(value: Int): Int = value
    }
    v.startCoroutine(1, Continuation(EmptyCoroutineContext) { it.getOrThrow() })
}

fun main() {
    val o: suspend () -> Int = object : suspend () -> Int {
        override suspend fun invoke(): Int = 42
    }
    println(o is SuspendFunction0<*>)
    println(o is SuspendFunction1<*, *>)
}
