import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

// Regression: a user CoroutineScope extension must resolve inside runBlocking,
// and its nested produce lambda must receive the produced channel correctly.
fun CoroutineScope.produceValue(): ReceiveChannel<Int> = produce {
    send(7)
}

fun main() = runBlocking {
    println(produceValue().receive())
}
