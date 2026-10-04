import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

// Regression for Flow.collect losing a local non-suspend collector reference.

fun main() = runBlocking {
    val source = flowOf(1, 2, 3)
    val collector = { value: Int -> println(value) }
    source.collect(collector)
}
