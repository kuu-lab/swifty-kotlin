import java.util.Timer
import java.util.TimerTask
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

private fun createEmptyTimer() { Timer() }

private fun scheduleOneShot(done: CountDownLatch) {
    Timer().schedule(object : TimerTask() {
        override fun run() { done.countDown() }
    }, 100L)
}

private fun schedulePeriodic(done: CountDownLatch) {
    Timer().schedule(object : TimerTask() {
        private var count = 0
        override fun run() {
            count += 1
            if (count == 3) {
                cancel()
                done.countDown()
            }
        }
    }, 100L, 50L)
}

fun main() {
    val done = CountDownLatch(2)
    createEmptyTimer()
    scheduleOneShot(done)
    schedulePeriodic(done)
    System.gc()
    val tasksCompleted = done.await(5L, TimeUnit.SECONDS)
    check(tasksCompleted)
    println(tasksCompleted)

    val retained = Timer()
    System.gc()
    val retainedTask = CountDownLatch(1)
    retained.schedule(object : TimerTask() {
        override fun run() { retainedTask.countDown() }
    }, 50L)
    val retainedCompleted = retainedTask.await(5L, TimeUnit.SECONDS)
    check(retainedCompleted)
    println(retainedCompleted)
    retained.cancel()
    println("main finished")
}
