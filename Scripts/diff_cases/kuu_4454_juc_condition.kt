import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.thread

// KUU-4454: ReentrantLock.ConditionObject await/signal/signalAll used to
// crash with `kk_array_get_inbounds precondition failed` because the
// implicit-receiver property accessor (`isHeldByCurrentThread` getter)
// dispatched on the inner ConditionObject instance instead of hopping the
// `$outer` chain to the ReentrantLock.
fun main() {
    val l0 = ReentrantLock()
    val c0 = l0.newCondition()
    for (name in listOf("signal", "signalAll", "await")) {
        try {
            when (name) {
                "signal" -> c0.signal()
                "signalAll" -> c0.signalAll()
                else -> c0.await()
            }
            println("$name: no-throw")
        } catch (e: IllegalMonitorStateException) {
            println("$name: illegal-monitor")
        }
    }

    val lock = ReentrantLock()
    val cond = lock.newCondition()
    lock.lock()
    cond.signal()
    cond.signalAll()
    lock.unlock()
    println("empty-signal-ok")

    val lock2 = ReentrantLock()
    val cond2 = lock2.newCondition()
    val waiting = CountDownLatch(1)
    val done = CountDownLatch(1)
    var observed = "none"
    val t = thread {
        lock2.lock()
        waiting.countDown()
        cond2.await()
        observed = "awaited"
        lock2.unlock()
        done.countDown()
    }
    waiting.await()
    while (!done.await(20, TimeUnit.MILLISECONDS)) {
        lock2.lock()
        cond2.signal()
        lock2.unlock()
    }
    t.join()
    println("handshake observed=$observed")

    val lock3 = ReentrantLock()
    val cond3 = lock3.newCondition()
    lock3.lock()
    val remaining = cond3.awaitNanos(30_000_000L)
    lock3.unlock()
    println("awaitNanos-timeout remaining<=0: ${remaining <= 0L}")

    val lock4 = ReentrantLock()
    val cond4 = lock4.newCondition()
    val ready = CountDownLatch(2)
    val finished = CountDownLatch(2)
    repeat(2) {
        thread {
            lock4.lock()
            ready.countDown()
            cond4.await()
            lock4.unlock()
            finished.countDown()
        }
    }
    ready.await()
    Thread.sleep(100)
    lock4.lock()
    cond4.signalAll()
    lock4.unlock()
    println("signalAll finished=${finished.await(5, TimeUnit.SECONDS)}")
}
