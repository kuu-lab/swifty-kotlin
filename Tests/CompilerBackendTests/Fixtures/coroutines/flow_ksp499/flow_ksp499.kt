import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.fold
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.reduce
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    val source = flow {
        emit(1)
        emit(2)
        emit(3)
    }
    println(source.map { it * 2 }.toList())
    println(source.filter { it % 2 == 1 }.first())
    println(source.fold(0) { acc, value -> acc + value })
    println(source.reduce { acc, value -> acc + value })
}
