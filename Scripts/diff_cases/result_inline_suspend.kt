// KUU-1345: Result callbacks inline into their enclosing coroutine.
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield

suspend fun value(): Int { yield(); return 7 }
suspend fun fail(): Int { yield(); throw IllegalStateException("suspended") }

class Ch {
    suspend fun flush() { yield(); println("flush") }
    suspend fun flushAndClose() { runCatching { flush() }.getOrThrow() }
}

fun nonLocalReturn(): Int {
    runCatching { return 9 }
    return -1
}

fun main() = runBlocking {
    val channel = Ch()
    runCatching { channel.flushAndClose() }.getOrThrow()
    channel.runCatching { flush() }.getOrThrow()
    val success = runCatching { value() }
    val failure = runCatching { fail() }
    println(success.getOrThrow())
    println(failure.exceptionOrNull()?.message)
    println(failure.getOrElse { value() })
    println(success.map { value() + it }.getOrThrow())
    println(failure.map { value() }.exceptionOrNull() === failure.exceptionOrNull())
    println(success.mapCatching { fail() }.exceptionOrNull()?.message)
    println(success.fold({ value() + it }, { fail() }))
    println(failure.fold({ fail() }, { value() }))
    success.onSuccess { println(value() + it) }.onFailure { fail() }
    failure.onFailure { println(value()) }.onSuccess { fail() }
    println(failure.recover { value() }.getOrThrow())
    println(success.recover { fail() }.getOrThrow())
    println(failure.recoverCatching { value() }.getOrThrow())
    println(failure.recoverCatching { fail() }.exceptionOrNull()?.message)
    println(runCatching { failure.recover { fail() } }.exceptionOrNull()?.message)
    println(nonLocalReturn())
    val interrupted = runCatching { fail(); println("unreachable"); value() }
    println(interrupted.exceptionOrNull()?.message)
    println(runCatching {
        try { fail() } catch (exception: IllegalStateException) { value() }
        finally { println("finally") }
    }.getOrThrow())
}
