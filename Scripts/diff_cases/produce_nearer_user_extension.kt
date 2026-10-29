import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun CoroutineScope.produce(block: () -> Int): Int = block() + 10
fun main() = runBlocking { println(produce { 3 }) }
