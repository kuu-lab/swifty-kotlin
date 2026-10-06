import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val transformed = flow<Int> {
        println("start")
        emit(1)
        emit(2)
    }.transform<Int, String> { value ->
        emit("value=$value")
    }
    println("constructed")
    repeat(2) { index ->
        println("repeat=$index")
        try {
            transformed.collect { value ->
                println(value)
                throw IllegalStateException("downstream")
            }
        } catch (e: IllegalStateException) {
            println(e.message)
        }
    }
    val ranged = flow<Int> {
        println("start")
        emit(1)
        emit(2)
    }.transform<Int, String> { value ->
        emit("value=$value")
    }
    for (index in 0..1) {
        println("for=$index")
        try {
            ranged.collect { value ->
                println(value)
                throw IllegalStateException("downstream")
            }
        } catch (e: IllegalStateException) {
            println(e.message)
        }
    }
    println("success")
    val successful = flowOf(1, 2).transform<Int, String> { emit("value=$it") }
    repeat(2) { successful.collect { println(it) } }
    println("after")
}
