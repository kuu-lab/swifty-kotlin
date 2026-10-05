import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.*

suspend fun loopScope(iterations: Int) {
    val stream = flowOf(1).transform<Int, Int> { emit(it) }
    val alias = stream
    repeat(iterations) {
        alias.collect { println(it) }
    }
    println("scope finished")
}

fun main() = runBlocking {
    loopScope(0)
    loopScope(3)
    repeat(2) {
        val stream = flowOf(2).transform<Int, Int> { emit(it) }
        stream.collect { println(it) }
    }
    val stream = flowOf(3).transform<Int, Int> { emit(it) }
    repeat(2) {
        try {
            stream.collect { throw IllegalStateException("collector failed") }
        } catch (e: IllegalStateException) {
            println(e.message)
        }
    }
    stream.collect { println(it) }
}
