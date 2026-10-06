// Regression coverage for KUU-951: passing a *named* suspend function value
// (rather than a lambda literal) as the `block` argument of produce/actor
// must bind the bundled CoroutineScope.produce / actor overloads, inferring
// E from the value's declared `suspend ProducerScope<E>.() -> Unit` /
// `suspend ActorScope<E>.() -> Unit` receiver type.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

// KUU-1138: opaque returned values retain their closure ABI, including multiple captures.
fun producerBlock(base: Int, step: Int): suspend ProducerScope<Int>.() -> Unit = {
    send(base)
    yield()
    send(base + step)
}

fun actorBlock(done: Channel<Int>, bias: Int): suspend ActorScope<Int>.() -> Unit = {
    var acc = bias
    for (msg in channel) { acc += msg }
    done.send(acc)
}

fun main() = runBlocking {
    // The annotation itself is a function type declared inside a lambda body.
    val f: suspend ProducerScope<Int>.() -> Unit = {
        send(1)
        send(2)
    }
    var total = 0
    for (v in produce(block = f)) { total += v }
    println("named: $total")
    total = 0
    for (v in produce(capacity = 2, block = f)) { total += v }
    println("capacity: $total")
    total = 0
    for (v in produce(block = producerBlock(3, 1))) { total += v }
    println("opaque: $total")

    // actor with a function-value block; rendezvous keeps output order stable.
    val done = Channel<Int>(capacity = 1)
    val g: suspend ActorScope<Int>.() -> Unit = {
        var acc = 0
        for (msg in channel) { acc += msg }
        println("actor sum: $acc")
        done.send(1)
    }
    val a1 = actor(block = g)
    a1.send(10)
    a1.send(20)
    a1.close()
    done.receive()

    val a2 = actor(capacity = 2, block = actorBlock(done, 10))
    a2.send(4)
    a2.send(5)
    a2.close()
    println("opaque actor: ${done.receive()}")

    println("done")
}
