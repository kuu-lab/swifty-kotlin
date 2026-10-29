import java.util.Date
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.concurrent.timer
import kotlin.concurrent.fixedRateTimer
import kotlin.concurrent.schedule

fun main() {
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    val loader = Thread.currentThread().contextClassLoader
    val worker = thread(start = false, isDaemon = true, contextClassLoader = loader, name = "worker", priority = 7) {
        println(Thread.currentThread().contextClassLoader === loader)
        println(Thread.currentThread().name)
        println(Thread.currentThread().isDaemon)
        println(Thread.currentThread().priority)
        entered.countDown()
        release.await()
    }
    println(worker.isAlive)
    worker.start()
    println(entered.await(5L, TimeUnit.SECONDS))
    release.countDown()
    worker.join()
    println(worker.isAlive)
    try {
        worker.start()
    } catch (_: IllegalThreadStateException) {
        println("already started")
    }

    val ready = CountDownLatch(4)
    val a = timer(name = "a", daemon = true, initialDelay = 0L, period = 1000L) { ready.countDown() }
    val past = java.lang.System.currentTimeMillis() - 1000L
    var fixedDelayTimeWasAdjusted = false
    val b = timer(name = "b", daemon = true, startAt = Date(past), period = 1000L) {
        fixedDelayTimeWasAdjusted = scheduledExecutionTime() > past
        ready.countDown()
    }
    val c = fixedRateTimer(name = "c", daemon = true, initialDelay = 0L, period = 1000L) { ready.countDown() }
    var defaultTimerName = false
    val d = fixedRateTimer(daemon = true, startAt = Date(), period = 1000L) {
        defaultTimerName = Thread.currentThread().name.startsWith("Timer-")
        ready.countDown()
    }
    println(ready.await(5L, TimeUnit.SECONDS))
    println(fixedDelayTimeWasAdjusted)
    println(defaultTimerName)
    val second = CountDownLatch(1)
    a.schedule(0L) { second.countDown() }
    println(second.await(3L, TimeUnit.SECONDS))
    a.cancel()
    b.cancel()
    c.cancel()
    d.cancel()
}
