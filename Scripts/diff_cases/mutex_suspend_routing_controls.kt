import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    val gate = Mutex()
    println(gate.withLock { 7 })
    println(gate.isLocked)
    val permits = Semaphore(1)
    println(permits.withPermit { 8 })
    println(permits.availablePermits)
    val channel = Channel<Int>(1)
    channel.send(42)
    println(channel.receive())
    channel.close()
    println("closed")
}
