import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*

fun main() = runBlocking {
    val gate = Mutex()
    gate.tryLock()
    val cancelled = launch(start = CoroutineStart.UNDISPATCHED) {
        try {
            gate.lock()
            println("unexpected acquisition")
            gate.unlock()
        } catch (e: CancellationException) {
            println("cancelled waiter")
        }
    }
    cancelled.cancel()
    cancelled.join()
    val waiter = launch(start = CoroutineStart.UNDISPATCHED) {
        gate.lock()
        println("next waiter")
        gate.unlock()
    }
    println("release after cancel")
    gate.unlock()
    waiter.join()
    println(gate.isLocked)

    val owner = Any()
    gate.tryLock()
    val owned = launch(start = CoroutineStart.UNDISPATCHED) {
        try {
            gate.lock(owner)
            println("unexpected owned acquisition")
            gate.unlock(owner)
        } catch (e: CancellationException) {
            println("cancelled owner waiter")
        }
    }
    owned.cancel()
    owned.join()
    gate.unlock()
    println(gate.holdsLock(owner))
    println(gate.tryLock())
    gate.unlock()

    val handoff = Mutex()
    handoff.tryLock()
    val resumed = launch(start = CoroutineStart.UNDISPATCHED) {
        try {
            handoff.lock()
            println("unexpected handoff acquisition")
            handoff.unlock()
        } catch (e: CancellationException) {
            println("cancelled after handoff")
        }
    }
    handoff.unlock()
    resumed.cancel()
    resumed.join()
    println(handoff.isLocked)

    val fast = Mutex()
    val fastOwner = Any()
    val fastWaiter = launch(start = CoroutineStart.UNDISPATCHED) {
        coroutineContext.job.cancel()
        fast.lock()
        println("cancelled fast path")
        fast.unlock()
        fast.lock(fastOwner)
        println(fast.holdsLock(fastOwner))
        fast.unlock(fastOwner)
    }
    fastWaiter.join()
    println(fast.isLocked)
}
