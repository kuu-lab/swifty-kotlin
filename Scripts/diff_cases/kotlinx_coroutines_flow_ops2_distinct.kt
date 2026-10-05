import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val repeated = flowOf(1, 1, 2, 2, 1, 1).distinctUntilChanged()
    println(repeated.toList())
    println(repeated.toList())
    println(flowOf<Int?>(null, null, 1, 1, null).distinctUntilChanged().toList())
    println(flowOf(1, 3, 2, 4, 1).distinctUntilChanged { old, new -> old % 2 == new % 2 }.toList())
    println(flowOf("a", "b", "cc", "dd", "e").distinctUntilChangedBy { it.length }.toList())
    println(flowOf(1, 2, 3).distinctUntilChangedBy { null }.toList())
    println(emptyFlow<Int>().distinctUntilChanged().toList())
}
