import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

// Regression: emissions after a suspend point must remain attached to collect.
fun main() = runBlocking {
    val values = mutableListOf<Int>()
    flow {
        emit(1)
        delay(1)
        emit(2)
    }.collect { values.add(it) }
    println("values: ${values.size}")
}
