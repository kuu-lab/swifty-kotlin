// KUU-2686: `Mutex.onLock(owner)` routes the owner into the lock
// acquisition — holdsLock(owner) observes it and unlock(owner) validates
// it, the same owner semantics `Mutex.lock(owner)` has.
import kotlinx.coroutines.*
import kotlinx.coroutines.selects.*
import kotlinx.coroutines.sync.*

fun main() = runBlocking {
    val m = Mutex()
    val owner = Any()

    println(select<String> { m.onLock(owner) { "locked" } })
    println(m.isLocked)
    println(m.holdsLock(owner))
    println(m.holdsLock(Any()))

    // Wrong-owner unlock keeps the lock held and throws, like unlock(owner)
    // on a lock acquired through `lock(owner)`.
    try {
        m.unlock(Any())
        println("no-throw")
    } catch (e: IllegalStateException) {
        println("ise")
    }
    println(m.isLocked)
    println(m.holdsLock(owner))
    m.unlock(owner)
    println(m.isLocked)

    // Anonymous onLock still acquires anonymously.
    println(select<String> { m.onLock { "anon" } })
    println(m.isLocked)
    m.unlock()
    println(m.isLocked)

    // A select whose onLock loses to a held mutex falls back to onTimeout;
    // the existing owner keeps the lock.
    m.lock(owner)
    println(select<String> { m.onLock { "unexpected" }; onTimeout(1L) { "timeout" } })
    println(m.holdsLock(owner))
    m.unlock(owner)
    println("done")
}
