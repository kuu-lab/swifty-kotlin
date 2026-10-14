import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*

fun main() = runBlocking {
    val gate = Mutex()
    gate.tryLock()
    val waiter = launch(start = CoroutineStart.UNDISPATCHED) {
        gate.lock()
        println("acquired")
        gate.unlock()
    }
    println("release")
    gate.unlock()
    waiter.join()
    println(gate.isLocked)
}
