import java.util.concurrent.*
import java.util.concurrent.atomic.*

// KUU-3363: Keep the reported java.util.concurrent wildcard-import surface covered.
fun main() {
    val flag = AtomicBoolean(false)
    println(flag.get())

    val reference = AtomicReference("x")
    println(reference.get())

    val number = AtomicLong(1)
    println(number.get())

    val latch = CountDownLatch(1)
    println(latch.count)
    latch.countDown()
    println(latch.await(1, TimeUnit.SECONDS))

    println(Semaphore(1).availablePermits())
    println(CyclicBarrier(1).await())
    println(ThreadLocal<String>().get())

    val executor = Executors.newSingleThreadExecutor()
    println(executor.isShutdown)
    executor.shutdown()

    println(Callable { 42 }.call())
}
