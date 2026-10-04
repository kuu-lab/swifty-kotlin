import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val empty = emptyFlow<Int>()
    println(empty.firstOrNull())
    println(empty.lastOrNull())
    println(empty.singleOrNull())
    try {
        empty.last()
    } catch (e: NoSuchElementException) {
        println("empty last")
    }
    println(flowOf(1, 2, 3).firstOrNull())
    println(flowOf(1, 2, 3).firstOrNull { it > 1 })
    println(flowOf(1, 2, 3).firstOrNull { it > 5 })
    println(flowOf(1, 2, 3).last())
    println(flowOf(1, 2, 3).lastOrNull())
    println(flowOf(7).singleOrNull())
    println(flowOf(1, 2).singleOrNull())
    println(flowOf<Int?>(null, 2).firstOrNull())
    println(flowOf<Int?>(1, null).last())
    println(flowOf<Int?>(null).singleOrNull())
    println(flowOf<Int?>(null, 2).singleOrNull())
    println(flowOf(1, 2, 3, 4).count { it % 2 == 0 })
    println(empty.count { true })
    println(flow<Int> {
        emit(9)
        throw IllegalStateException("unreachable")
    }.firstOrNull())
    println(flow<Int> {
        emit(1)
        emit(2)
        throw IllegalStateException("unreachable")
    }.singleOrNull())
}
