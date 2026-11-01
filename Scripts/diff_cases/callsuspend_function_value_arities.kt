// callSuspend/callSuspendBy invoke a suspend callable through its suspend
// function value: suspend references register no KCallable.call invoker.
import kotlin.reflect.full.callSuspend
import kotlin.reflect.full.callSuspendBy
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking

suspend fun none(): String {
    delay(1)
    return "none"
}

suspend fun pair(a: Int, b: String): String {
    delay(1)
    return "$b$a"
}

class Counter(private val base: Int) {
    suspend fun add(x: Int): Int {
        delay(1)
        return base + x
    }
}

fun plain(x: Int): Int = x + 100

fun main() = runBlocking {
    println(::none.callSuspend())
    println(::pair.callSuspend(7, "p"))
    println(Counter(3)::add.callSuspend(4))
    println(Counter::add.callSuspend(Counter(10), 5))
    println(::plain.callSuspend(1))
    val params = ::pair.parameters
    println(::pair.callSuspendBy(mapOf(params[1] to "q", params[0] to 9)))
    println(::plain.callSuspendBy(mapOf(::plain.parameters[0] to 2)))
}
