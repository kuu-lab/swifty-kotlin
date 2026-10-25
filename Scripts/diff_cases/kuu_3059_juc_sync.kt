import java.util.concurrent.CountDownLatch
import java.util.concurrent.CyclicBarrier
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit

// KUU-3059: blocking primitives — latch, semaphore, barrier — plus TimeUnit
// conversions. Single-threaded paths only so output is deterministic.
fun main() {
    val latch = CountDownLatch(1)
    println(latch.count)                    // 1
    latch.countDown()
    println(latch.count)                    // 0
    println(latch.await(1, TimeUnit.SECONDS)) // true
    latch.await()                           // returns immediately

    val sem = Semaphore(2)
    println(sem.availablePermits())         // 2
    println(sem.tryAcquire())               // true
    println(sem.tryAcquire(2))              // false
    println(sem.tryAcquire(1, 1, TimeUnit.SECONDS)) // true
    println(sem.drainPermits())             // 0 (both permits are held)
    sem.release(3)
    println(sem.availablePermits())         // 3
    sem.acquire(2)
    println(sem.availablePermits())         // 1
    sem.release()
    sem.release()
    println(sem.availablePermits())         // 3

    val barrier = CyclicBarrier(1)
    println(barrier.parties)                // 1
    println(barrier.await())                // 0 (last-arriver index)
    println(barrier.numberWaiting)          // 0
    println(barrier.isBroken)               // false
    println(barrier.await(1, TimeUnit.SECONDS)) // 0

    println(TimeUnit.SECONDS.toMillis(2))   // 2000
    println(TimeUnit.MILLISECONDS.toNanos(5)) // 5000000
    println(TimeUnit.MINUTES.toSeconds(3))  // 180
    println(TimeUnit.HOURS.convert(1, TimeUnit.DAYS)) // 24
    println(TimeUnit.NANOSECONDS.convert(1_500_000_000L, TimeUnit.SECONDS)) // 1500000000
}
