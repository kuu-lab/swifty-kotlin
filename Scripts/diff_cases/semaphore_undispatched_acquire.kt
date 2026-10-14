import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*
fun main() = runBlocking {
    val gate = Semaphore(1)
    gate.tryAcquire()
    val waiter = launch(start = CoroutineStart.UNDISPATCHED) {
        gate.acquire()
        println("acquired")
        gate.release()
    }
    println("release")
    gate.release()
    waiter.join()
    println(gate.availablePermits)
}
