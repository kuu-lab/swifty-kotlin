package kotlin.system

import kswiftk.internal.*

fun exitProcess(status: Int): Nothing = __exitProcess(status)

fun getTimeMicros(): Long = __getTimeMicros()

fun getTimeMillis(): Long = __getTimeMillis()

fun getTimeNanos(): Long = __getTimeNanos()

inline fun measureTimeMicros(block: () -> Unit): Long {
    val start = __getTimeMicros()
    block()
    return __getTimeMicros() - start
}

inline fun measureTimeMillis(block: () -> Unit): Long {
    val start = __getTimeMillis()
    block()
    return __getTimeMillis() - start
}

inline fun measureNanoTime(block: () -> Unit): Long {
    val start = __getTimeNanos()
    block()
    return __getTimeNanos() - start
}
