// KUU-1356: Mutex.lock(owner)/unlock(owner) — owner-token overloads.
// Covers the issue reproducer plus the upstream token contract:
// wrong-owner unlock throws IllegalStateException without releasing,
// unlock()/unlock(null) skips the check, and re-locking with the same
// owner throws instead of deadlocking.
// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*

fun main() = runBlocking {
    val m = Mutex()
    m.lock(this)
    println(m.isLocked)
    m.unlock(this)
    println(m.isLocked)

    val owner = Any()
    m.lock(owner)
    println(m.isLocked)
    try {
        m.unlock(Any())
        println("no-throw")
    } catch (e: IllegalStateException) {
        println("ise")
    }
    println(m.isLocked)
    m.unlock(owner)
    println(m.isLocked)

    m.lock(owner)
    m.unlock()
    println(m.isLocked)

    m.lock(owner)
    try {
        m.lock(owner)
        println("no-throw")
    } catch (e: IllegalStateException) {
        println("ise")
    }
    println(m.isLocked)
    m.unlock(owner)
    println(m.isLocked)
    println("done")
}
