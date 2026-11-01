// An actor block passed as a function value checkcasts its receiver to
// ActorScope; the shared produce launcher must register the actor channel
// as ActorScope while produce keeps ProducerScope.
@file:OptIn(kotlinx.coroutines.ObsoleteCoroutinesApi::class)

import kotlinx.coroutines.channels.ActorScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ProducerScope
import kotlinx.coroutines.channels.actor
import kotlinx.coroutines.channels.produce
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    val done = Channel<Int>(1)
    val consumer: suspend ActorScope<String>.() -> Unit = {
        var count = 0
        for (message in channel) {
            println("got $message")
            count += 1
        }
        done.send(count)
    }
    val mailbox = actor(capacity = 1, block = consumer)
    mailbox.send("a")
    mailbox.send("b")
    mailbox.close()
    println("count ${done.receive()}")

    val producer: suspend ProducerScope<Int>.() -> Unit = {
        send(1)
        send(2)
    }
    var total = 0
    for (value in produce(block = producer)) total += value
    println("total $total")
}
