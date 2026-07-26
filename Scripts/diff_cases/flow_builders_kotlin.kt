import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

// KSP-674: flowOf / emptyFlow / Iterable.asFlow are Kotlin source composed from
// flow { } (kk_flow_create) + emit (kk_flow_emit). This case pins their
// end-to-end parity with kotlinx.coroutines, including an outer-captured value
// in an explicit flow { } builder (the emitter-side capture path).

fun main() = runBlocking {
    // flowOf vararg iteration + operators
    flowOf(1, 2, 3)
        .map { it * 10 }
        .filter { it > 10 }
        .collect { println(it) }

    // emptyFlow emits nothing
    emptyFlow<Int>()
        .collect { println(it) }
    println("empty-done")

    // Iterable.asFlow + operators
    listOf(4, 5, 6)
        .asFlow()
        .map { it + 100 }
        .collect { println(it) }

    // Explicit flow { } capturing an outer val (emitter-side capture)
    val base = 1000
    flow {
        for (i in 1..3) {
            emit(base + i)
        }
    }.collect { println(it) }
}
