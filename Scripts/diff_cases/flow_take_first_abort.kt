// KUU-1224: validate take eagerly and stop upstream at the requested element.
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    for (count in listOf(0, -1)) {
        try {
            flowOf(1).take(count)
            println("invalid accepted")
        } catch (e: IllegalArgumentException) {
            println(e.message)
        }
    }
    val source = flow<Int> {
        try {
            println("start")
            emit(1)
            println("second")
            emit(2)
            throw IllegalStateException("unreachable")
        } finally {
            println("cleanup")
        }
    }
    val one = source.take(1)
    println(one.toList())
    println(one.toList())
    println(source.take(2).toList())
    println(source.first())
    println(source.take(2).take(1).toList())
    println(source.take(2).first())
    println(flowOf(1, 2).take(5).toList())
    println(emptyFlow<Int>().take(1).toList())
    println(flow<Int?> {
        emit(null)
        throw IllegalStateException("unreachable")
    }.first())
    try {
        emptyFlow<Int>().first()
    } catch (e: NoSuchElementException) {
        println("empty")
    }
    try {
        source.take(1).collect { throw IllegalArgumentException("downstream") }
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    try {
        flow<Int> { throw IllegalStateException("upstream") }.first()
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    Unit
}
