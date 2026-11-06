// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.runBlocking

// KUU-4348: `for (v in channel)` must resolve the bundled
// `Channel<E>.iterator()` extension instead of falling back to the
// `__kk_range_*` intrinsics.

fun main() = runBlocking {
    val ch = Channel<Int>(Channel.UNLIMITED)
    ch.trySend(7)
    ch.close()
    for (v in ch) {
        println(v)
    }
    println("done")
}
