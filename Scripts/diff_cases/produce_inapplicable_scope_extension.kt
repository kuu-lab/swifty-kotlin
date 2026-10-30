import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun CoroutineScope.produce(from: Int, to: Int): ReceiveChannel<Int> = produce {
    for (i in from..to) send(i)
}

fun main() = runBlocking {
    println(produce(1, 1).receive())
}
