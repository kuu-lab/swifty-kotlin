package java.util.concurrent

import java.lang.Runnable
import java.util.Timer
import java.util.TimerTask
import kotlin.system.System

public interface Delayed : Comparable<Delayed> {
    public fun getDelay(unit: TimeUnit): Long
}

public interface ScheduledFuture<V> : Delayed, Future<V>

public interface ScheduledExecutorService : ExecutorService {
    public fun schedule(command: Runnable, delay: Long, unit: TimeUnit): ScheduledFuture<*>
    public fun <V> schedule(callable: Callable<V>, delay: Long, unit: TimeUnit): ScheduledFuture<V>
    public fun scheduleAtFixedRate(
        command: Runnable,
        initialDelay: Long,
        period: Long,
        unit: TimeUnit,
    ): ScheduledFuture<*>
    public fun scheduleWithFixedDelay(
        command: Runnable,
        initialDelay: Long,
        delay: Long,
        unit: TimeUnit,
    ): ScheduledFuture<*>
}

/** Scheduled executor facade backed by the bundled Timer and worker pool. */
public open class ScheduledThreadPoolExecutor(corePoolSize: Int) : ScheduledExecutorService {
    private val workers: ExecutorService
    private val timer = Timer("ScheduledThreadPoolExecutor", true)
    private val scheduledTasks = ArrayList<CancelableScheduledTask>()
    private var shutdown = false

    init {
        if (corePoolSize <= 0) throw IllegalArgumentException("corePoolSize <= 0")
        workers = Executors.newFixedThreadPool(corePoolSize)
    }

    override fun execute(command: Runnable) = workers.execute(command)

    override fun schedule(command: Runnable, delay: Long, unit: TimeUnit): ScheduledFuture<*> =
        schedule(Callable {
            command.run()
            null
        }, delay, unit)

    override fun <V> schedule(callable: Callable<V>, delay: Long, unit: TimeUnit): ScheduledFuture<V> {
        ensureRunning()
        val future = FutureTask(callable)
        val dueNanos = System.nanoTime() + unit.toNanos(maxOf(0L, delay))
        val timerTask = object : TimerTask() {
            override fun run() {
                if (isShutdown) {
                    future.cancel(false)
                    return
                }
                try {
                    workers.execute(future)
                } catch (_: RejectedExecutionException) {
                    future.cancel(false)
                }
            }
        }
        val scheduled = TimerScheduledFuture(future, timerTask, dueNanos)
        scheduledTasks.add(scheduled)
        timer.schedule(timerTask, maxOf(0L, unit.toMillis(delay)))
        return scheduled
    }

    override fun scheduleAtFixedRate(
        command: Runnable,
        initialDelay: Long,
        period: Long,
        unit: TimeUnit,
    ): ScheduledFuture<*> = schedulePeriodic(command, initialDelay, period, unit, true)

    override fun scheduleWithFixedDelay(
        command: Runnable,
        initialDelay: Long,
        delay: Long,
        unit: TimeUnit,
    ): ScheduledFuture<*> = schedulePeriodic(command, initialDelay, delay, unit, false)

    private fun schedulePeriodic(
        command: Runnable,
        initialDelay: Long,
        interval: Long,
        unit: TimeUnit,
        fixedRate: Boolean,
    ): ScheduledFuture<*> {
        ensureRunning()
        if (interval <= 0L) throw IllegalArgumentException("period must be positive")
        val state = FutureTask(Callable { Unit })
        val dueNanos = System.nanoTime() + unit.toNanos(maxOf(0L, initialDelay))
        lateinit var scheduled: PeriodicScheduledFuture
        val timerTask = object : TimerTask() {
            override fun run() {
                if (isShutdown || state.isCancelled) {
                    scheduled.cancel(false)
                    return
                }
                try {
                    command.run()
                } catch (_: Throwable) {
                    scheduled.cancel(false)
                }
            }
        }
        scheduled = PeriodicScheduledFuture(state, timerTask, dueNanos)
        scheduledTasks.add(scheduled)
        val delayMillis = maxOf(0L, unit.toMillis(initialDelay))
        val intervalMillis = maxOf(1L, unit.toMillis(interval))
        if (fixedRate) timer.scheduleAtFixedRate(timerTask, delayMillis, intervalMillis)
        else timer.schedule(timerTask, delayMillis, intervalMillis)
        return scheduled
    }

    private fun ensureRunning() {
        if (shutdown) throw RejectedExecutionException("Executor is shutdown")
    }

    override fun shutdown() {
        if (shutdown) return
        shutdown = true
        for (task in scheduledTasks) task.cancel(false)
        scheduledTasks.clear()
        timer.cancel()
        workers.shutdown()
    }

    override fun shutdownNow(): List<Runnable> {
        shutdown()
        return workers.shutdownNow()
    }

    override val isShutdown: Boolean get() = shutdown
    override val isTerminated: Boolean get() = workers.isTerminated
    override fun awaitTermination(timeout: Long, unit: TimeUnit): Boolean = workers.awaitTermination(timeout, unit)
    override fun <V> submit(task: Callable<V>): Future<V> = workers.submit(task)
    override fun submit(task: Runnable): Future<*> = workers.submit(task)
    override fun <V> submit(task: Runnable, result: V): Future<V> = workers.submit(task, result)
    override fun <V> invokeAll(tasks: Collection<Callable<V>>): List<Future<V>> = workers.invokeAll(tasks)
    override fun <V> invokeAny(tasks: Collection<Callable<V>>): V = workers.invokeAny(tasks)
}

private interface CancelableScheduledTask {
    fun cancel(mayInterruptIfRunning: Boolean): Boolean
}

private class TimerScheduledFuture<V>(
    private val future: Future<V>,
    private val timerTask: TimerTask,
    private val dueNanos: Long,
) : ScheduledFuture<V>, CancelableScheduledTask {
    override fun cancel(mayInterruptIfRunning: Boolean): Boolean {
        timerTask.cancel()
        return future.cancel(mayInterruptIfRunning)
    }

    override val isCancelled: Boolean get() = future.isCancelled
    override val isDone: Boolean get() = future.isDone
    override fun get(): V = future.get()
    override fun get(timeout: Long, unit: TimeUnit): V = future.get(timeout, unit)
    override fun getDelay(unit: TimeUnit): Long = unit.convert(dueNanos - System.nanoTime(), TimeUnit.NANOSECONDS)
    override fun compareTo(other: Delayed): Int = getDelay(TimeUnit.NANOSECONDS).compareTo(other.getDelay(TimeUnit.NANOSECONDS))
}

private class PeriodicScheduledFuture(
    private val state: Future<Unit>,
    private val timerTask: TimerTask,
    private val dueNanos: Long,
) : ScheduledFuture<Unit>, CancelableScheduledTask {
    override fun cancel(mayInterruptIfRunning: Boolean): Boolean {
        timerTask.cancel()
        return state.cancel(mayInterruptIfRunning)
    }

    override val isCancelled: Boolean get() = state.isCancelled
    override val isDone: Boolean get() = state.isDone
    override fun get() = state.get()
    override fun get(timeout: Long, unit: TimeUnit) = state.get(timeout, unit)
    override fun getDelay(unit: TimeUnit): Long = unit.convert(dueNanos - System.nanoTime(), TimeUnit.NANOSECONDS)
    override fun compareTo(other: Delayed): Int = getDelay(TimeUnit.NANOSECONDS).compareTo(other.getDelay(TimeUnit.NANOSECONDS))
}
