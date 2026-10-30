import java.util.Timer
import java.util.TimerTask
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

private fun scheduleCapturedTimer(done: CountDownLatch) {
    val timer = Timer()
    timer.schedule(object : TimerTask() {
        override fun run() {
            timer.purge()
            done.countDown()
        }
    }, 100L)
}

fun main() {
    val done = CountDownLatch(1)
    scheduleCapturedTimer(done)
    System.gc()
    val completed = done.await(5L, TimeUnit.SECONDS)
    check(completed)
    println(completed)
    repeat(10) {
        System.gc()
        Thread.sleep(100L)
    }
    println("main finished")
}
