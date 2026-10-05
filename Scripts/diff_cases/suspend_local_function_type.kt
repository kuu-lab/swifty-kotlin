// KUU-1008: a suspend function type in a lambda-local declaration must not
// resolve as a named type called "suspend".
import kotlinx.coroutines.*

fun main() = runBlocking {
    val block: suspend () -> Int = { 42 }
    println(block())

    var transform: suspend (Int) -> Int = { it + 1 }
    println(transform(41))
    transform = { it * 2 }
    println(transform(21))

    val captured = 40
    val delayed: suspend () -> Int = {
        delay(1)
        captured + 2
    }
    println(delayed())

    if (true) {
        val nested: suspend () -> Int = { captured + 3 }
        println(nested())
    }
}
