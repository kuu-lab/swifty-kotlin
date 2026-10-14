// KUU-2055: Mutex(locked = false) exposes the upstream initial-state factory.
// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*

fun use() { val lock = Mutex(true) }

fun main() = runBlocking {
    println(Mutex().isLocked)
    val lock = Mutex(true)
    println(lock.isLocked)
    lock.unlock()
    println(lock.isLocked)

    val unlocked = Mutex(false)
    println(unlocked.isLocked)
    println(unlocked.tryLock())
    unlocked.unlock()
    println(Mutex(locked = false).isLocked)

    val initiallyLocked = true
    val named = Mutex(locked = initiallyLocked)
    println(named.isLocked)
    println(named.tryLock())
    val owner = Any()
    println(named.holdsLock(owner))
    try {
        named.unlock(owner)
        println("no-throw")
    } catch (e: IllegalStateException) {
        println("owner-mismatch")
    }
    println(named.isLocked)
    named.unlock(null)
    println(named.tryLock())
    named.unlock()

    val gate = Mutex(true)
    println("release")
    gate.unlock()
    gate.lock()
    println("acquired")
    gate.unlock()
    println(gate.isLocked)
}
