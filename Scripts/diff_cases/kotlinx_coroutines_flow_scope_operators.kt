// KSP-1577: buffering/context modifiers stay pass-throughs while cancellable,
// onEmpty and collectLatest keep their value-stream semantics.
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    // buffer / flowOn are degenerate in the synchronous cold-flow model but
    // keep the API surface (and pass-through semantics on both stacks).
    flowOf(1, 2, 3)
        .buffer(4)
        .flowOn(Dispatchers.Default)
        .collect { println("buffered: $it") }

    // cancellable() re-checks the ambient job between emissions; an active
    // job emits everything just like the unmodified flow.
    flowOf(4, 5, 6)
        .cancellable()
        .collect { println("cancellable: $it") }

    // collectLatest is a sequential collect in the cold model: every element
    // reaches the action in order.
    flowOf(7, 8, 9).collectLatest { println("latest: $it") }

    // onEmpty runs the action only when upstream emitted nothing.
    emptyFlow<Int>()
        .onEmpty { println("empty: fallback ran") }
        .collect { println("never: $it") }
    flowOf(10)
        .onEmpty { println("never: should not print") }
        .collect { println("nonEmpty: $it") }

    println("done")
}
