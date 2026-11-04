// KUU-4133 regression: Boolean elements sent through channelFlow/produce must
// keep their Any-erased BoolBox identity at the channel-receive element
// boundary. runtimeFlowMaybeUnbox previously collapsed BoolBox to a raw 0/1
// before the value reached the collector's erased list, so `send(true)`
// printed `[1]` instead of JVM's `[true]`. Operator arguments (take counts,
// predicate decisions) still collapse to scalars.
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    // channelFlow / callbackFlow producer sends
    println(channelFlow { send(true) }.toList())
    println(channelFlow { send(false) }.toList())
    println(channelFlow { send(true); send(false) }.toList())
    println(channelFlow { trySend(true) }.toList())
    println(callbackFlow { trySend(true); close() }.toList())
    println(channelFlow { send(true) }.toList() == listOf(true))

    // Other erased send element types were already preserved
    println(channelFlow { send(1) }.toList())
    println(channelFlow { send('y') }.toList())
    println(channelFlow { send(2.5) }.toList())

    // Elements keep their box through operator chains and typed collectors
    println(channelFlow { send(true); send(false) }.filter { it }.toList())
    println(channelFlow { send(true); send(false) }.take(2).toList())
    println(channelFlow { send(true); send(false) }.takeWhile { it }.toList())
    println(channelFlow { send(false); send(true) }.dropWhile { !it }.toList())
    println(channelFlow { send(true) }.map { !it }.toList())
    channelFlow { send(true) }.collect { println("collected:$it") }
    channelFlow { send(false) }.collect { println("collected:$it") }
    println(channelFlow { send(false) }.first())
    println(channelFlow { send(true) }.single())

    // Typed channel send/receive still round-trips through the box
    val produced = produce<Boolean> { send(true); close() }
    println(produced.receive())
    val channel = Channel<Boolean>(4)
    channel.send(false)
    println(channel.receiveCatching().getOrNull())

    // flow { } emit and flowOf were already correct (KUU-4123 path)
    println(flow { emit(true) }.toList())
    println(flowOf(true, false).toList())
    println(flow { emit(false) }.toList() == listOf(false))
}
