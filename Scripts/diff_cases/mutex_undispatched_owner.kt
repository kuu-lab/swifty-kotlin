import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*

fun main() = runBlocking {
    val gate = Mutex()
    val first = Any()
    val second = Any()
    gate.lock(first)
    try {
        gate.lock(first)
        println("unexpected reentry")
    } catch (e: IllegalStateException) {
        println("same owner")
    }
    val waiter = launch(start = CoroutineStart.UNDISPATCHED) {
        gate.lock(second)
        println(gate.holdsLock(second))
        try {
            gate.unlock(first)
            println("unexpected unlock")
        } catch (e: IllegalStateException) {
            println("wrong owner")
        }
        gate.unlock(second)
    }
    println("release owner")
    gate.unlock(first)
    waiter.join()
    println(gate.isLocked)
    gate.lock(null)
    gate.unlock(null)
    println(gate.isLocked)
}
