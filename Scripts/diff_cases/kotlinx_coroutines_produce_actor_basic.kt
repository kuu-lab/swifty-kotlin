// Regression coverage for the bundled CoroutineScope.produce / actor builders
// (KSP-1573): produce yields a ReceiveChannel whose values are consumed by
// iteration, and actor yields a SendChannel that processes messages on the
// coroutine it launches.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    // produce: emits a value sequence, consumed via consumeEach-equivalent loop
    val produced = produce {
        send(10)
        send(20)
        send(30)
    }
    var total = 0
    for (v in produced) {
        total += v
    }
    println("produced total: $total")

    // producer block captures enclosing locals
    val base = 7
    val captured = produce {
        send(base + 1)
        send(base * 10)
    }
    val seen = mutableListOf<Int>()
    for (v in captured) {
        seen.add(v)
    }
    println("captured: ${seen.size}")

    // send arguments may reference bindings declared inside the producer
    // lambda (the element-type send-scan must not reject them)
    val looped = produce {
        for (i in 1..3) {
            send(i)
        }
        val extra = 9
        send(extra)
    }
    var seenLast = 0
    for (v in looped) {
        seenLast = v
    }
    println("looped last: $seenLast")

    // actor: SendChannel processing messages on the launched coroutine
    // (block captures enclosing locals)
    val offset = 100
    val greeter = actor<Int> {
        for (msg in channel) {
            println("actor got: ${msg + offset}")
        }
    }
    greeter.send(7)
    greeter.send(8)
    greeter.close()

    println("done")
}
