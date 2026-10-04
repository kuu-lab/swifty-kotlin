// runBlocking must wait for an actor's message processing after its body exits.
// Sending and closing the mailbox do not themselves wait for that processing.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() {
    runBlocking {
        val worker = actor<Int> {
            val value = channel.receive()
            delay(10)
            println("processed: $value")
        }
        worker.send(7)
        worker.close()
    }
    println("done")
}
