// KUU-1659: Mutex.holdsLock(owner) reports the current owner by identity.
// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*

data class Owner(val id: Int)

fun main() = runBlocking {
    val mutex = Mutex()
    val owner = Owner(7)
    val equalButDistinctOwner = Owner(7)

    println(owner == equalButDistinctOwner)
    println(mutex.holdsLock(owner))
    mutex.lock(owner)
    println(mutex.holdsLock(owner))
    println(mutex.holdsLock(equalButDistinctOwner))
    println(mutex.holdsLock(Owner(7)))
    println(mutex.isLocked)
    mutex.unlock(owner)
    println(mutex.holdsLock(owner))

    mutex.lock()
    println(mutex.holdsLock(owner))
    mutex.unlock()
}
