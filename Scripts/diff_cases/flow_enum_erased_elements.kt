// KUU-4123 regression: enum elements crossing erased flow/channel storage must
// keep their enum identity. A suspend-builder `emit`/`send` previously arrived
// at `toList` as a raw ordinal, so the collected list printed `[0]` and failed
// `==` against `listOf(Color.RED)` while `flowOf` stayed correct.
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.channels.*

enum class Color { RED, GREEN, BLUE }

fun main() = runBlocking {
    // flow { } suspend-builder emission
    println(flow { emit(Color.RED) }.toList())
    println(flow { emit(Color.RED); emit(Color.GREEN) }.toList())
    println(flow { emit(Color.RED) }.toList() == listOf(Color.RED))
    println(flow { emit(Color.RED) }.toList() == flowOf(Color.RED).toList())

    // channelFlow / callbackFlow producer sends
    println(channelFlow { send(Color.GREEN) }.toList())
    println(channelFlow { send(Color.RED) }.toList() == listOf(Color.RED))
    println(channelFlow { trySend(Color.BLUE) }.toList())
    println(callbackFlow { trySend(Color.BLUE); close() }.toList())

    // Typed channel send/receive still round-trips through the box
    val produced = produce<Color> { send(Color.RED); close() }
    println(produced.receive())
    val channel = Channel<Color>(4)
    channel.send(Color.GREEN)
    println(channel.receiveCatching().getOrNull())

    // Unaffected paths stay correct
    println(flow { emit(Color.BLUE) }.first())
    val manual = mutableListOf<Color>()
    flow { emit(Color.GREEN) }.collect { manual.add(it) }
    println(manual == listOf(Color.GREEN))
    println(flow<Color?> { emit(null) }.toList())
    println(flow { emit(42) }.toList())
    println(flow { emit(Unit) }.toList())
}
