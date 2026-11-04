import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

// KUU-4045: Flow.collect() used as a no-arg terminal must resolve to the
// bundled `suspend fun Flow<*>.collect()` overload and drain the flow for
// side effects instead of failing overload resolution. The inline
// flow-builder multi-emit chain and the `Flow<*>` receiver shape are
// covered together.
fun main() = runBlocking {
    // no-arg collect on a cold flow: collects and discards the elements.
    flow { emit(1); emit(2) }.collect()
    println("cold drained")

    // no-arg collect must still run upstream operators for side effects.
    flowOf(1, 2, 3).onEach { println("each:$it") }.collect()
    println("onEach drained")

    // receiver statically typed Flow<*>.
    val starred: Flow<*> = flowOf("x", "y")
    starred.collect()
    println("star drained")

    // multi-statement builder lambda chained directly into collect { }.
    flow { emit(10); emit(20) }.collect { println("value:$it") }
}
