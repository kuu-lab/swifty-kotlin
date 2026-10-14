import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*

// These functions are also compiled as an independent producer library.
suspend fun acquireGate(gate: Mutex) {
    gate.lock()
}

suspend fun acquireOwnedGate(gate: Mutex, owner: Any) {
    gate.lock(owner)
}

fun main() = runBlocking {
    val gate = Mutex()
    gate.tryLock()
    val waiter = launch(start = CoroutineStart.UNDISPATCHED) {
        acquireGate(gate)
        println("library acquired")
        gate.unlock()
    }
    println("release library")
    gate.unlock()
    waiter.join()
    println(gate.isLocked)

    val owner = Any()
    gate.tryLock()
    val owned = launch(start = CoroutineStart.UNDISPATCHED) {
        acquireOwnedGate(gate, owner)
        println(gate.holdsLock(owner))
        gate.unlock(owner)
    }
    println("release owned library")
    gate.unlock()
    owned.join()
    println(gate.isLocked)
}
