// KUU-3720: An inapplicable nearer overload must not hide imported produce.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun CoroutineScope.produce(required: String): Int = required.length

fun main() = runBlocking {
    val channel: ReceiveChannel<Int> = produce { send(7) }
    println(channel.receive())
}
