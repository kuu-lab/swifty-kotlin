import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.selects.*

fun main() = runBlocking {
    flow<Int> {
        coroutineScope {
            val signal = Channel<Int>(0)
            launch { delay(1); signal.send(7) }
            select<Unit> { signal.onReceive { emit(it) } }
        }
    }.take(1).collect { println("selected: $it") }
    println("done")
}
