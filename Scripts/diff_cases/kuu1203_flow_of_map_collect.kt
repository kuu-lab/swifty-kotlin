// KUU-1203: Flow.map through a shared stdlib artifact emitted garbage integers.
// The artifact serialized non-inline `map`'s callback parameter as
// non-local-return-capable, so the transform lambda stayed a raw callable
// instead of a boxed FunctionN and produced pointer-derived output.

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    // Exact issue repro.
    flowOf(10, 20, 30).map { it * 2 }.collect { println(it) }

    // Stored transform lambda through the same imported boundary.
    val timesTen = { value: Int -> value * 10 }
    flowOf(1, 2).map(timesTen).collect { println(it) }

    // Capturing transform through the imported boundary.
    val offset = 100
    flowOf(3, 4).map { it + offset }.collect { println(it) }

    // Chained operators keep each intermediate map's callback boxed.
    flowOf(5, 6).map { it + 1 }.map { it * 3 }.collect { println(it) }
}
