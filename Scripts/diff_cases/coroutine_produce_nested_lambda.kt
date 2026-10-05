import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val source = flowOf(4, 5, 6)
    val v = "outer"
    val ch = produce {
        source.collect { v -> send(v) }
    }
    println(ch.receive())
    println(ch.receive())
    println(ch.receive())
    println(v)

    val offset = 10
    val implicit = produce {
        source.collect { send(it + offset) }
    }
    println(implicit.receive())
    println(implicit.receive())
    println(implicit.receive())
    println("done")
}
