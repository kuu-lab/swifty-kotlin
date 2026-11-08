// NOTE: Requires kotlinx-coroutines on classpath.
import kotlinx.coroutines.sync.*

fun main() {
    val s = Semaphore(2, 1)
    println(s.availablePermits)  // 1
    println(s.tryAcquire())      // true
    println(s.availablePermits)  // 0
    println(s.tryAcquire())      // false
    s.release()
    println(s.availablePermits)  // 1

    val s2 = Semaphore(3)
    println(s2.availablePermits)  // 3

    val s3 = Semaphore(permits = 4, acquiredPermits = 2)
    println(s3.availablePermits)  // 2

    val s4 = Semaphore(2, acquiredPermits = 1)
    println(s4.availablePermits)  // 1
}
