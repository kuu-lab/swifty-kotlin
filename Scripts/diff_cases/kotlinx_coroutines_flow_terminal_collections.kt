import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val source = flowOf(3, 1, 3, 2)
    println(source.toSet())
    println(emptyFlow<Int>().toSet())
    val destination = mutableListOf(9)
    println(source.toCollection(destination))
    println(destination)
    val wide: MutableCollection<Any?> = mutableListOf<Any?>("seed")
    println(flowOf<Int?>(null, 1).toCollection(wide))
    val set = linkedSetOf(9)
    println(source.toSet(set))
    println(set)
    println(flowOf<Int?>(null, 1, null).toSet())
}
