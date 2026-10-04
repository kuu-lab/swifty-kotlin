import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

// Regression for Flow.collect losing a forwarded non-suspend collector reference.

fun runCollect(source: Flow<Int>, collector: (Int) -> Unit) = runBlocking {
    source.collect(collector)
}

fun main() {
    runCollect(flowOf(1, 2, 3)) { value -> println(value) }
}
