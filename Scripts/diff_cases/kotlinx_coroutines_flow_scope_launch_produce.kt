// KSP-1577: Flow<->coroutine/channel bridging operators — launchIn runs the
// collection in the given scope's Job, produceIn forwards elements through a
// ReceiveChannel.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    // launchIn collects inside the given scope; join() makes the
    // pre-print ordering deterministic on both stacks.
    val scope = CoroutineScope(Job())
    val collected = mutableListOf<Int>()
    val job = flowOf(1, 2, 3)
        .onEach { collected.add(it) }
        .launchIn(scope)
    job.join()
    println("launchIn: $collected")

    // produceIn streams each element through the returned channel, which
    // closes when the upstream collection finishes.
    val channel = flowOf(4, 5, 6).produceIn(scope)
    val produced = mutableListOf<Int>()
    for (item in channel) {
        produced.add(item)
    }
    println("produceIn: $produced")

    println("done")
}
