package java.util

import java.lang.Runnable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.concurrent.Volatile
import kotlin.system.System

/** A single-worker timer for delayed and periodic tasks. */
@Suppress("UNUSED_PARAMETER")
public class Timer private constructor(name: String, marker: Unit) {
    private val executor = Executors.newSingleThreadExecutor()

    @Volatile
    private var cancelled: Boolean = false

    public constructor() : this("Timer", Unit)

    public constructor(isDaemon: Boolean) : this("Timer", Unit)

    public constructor(name: String) : this(name, Unit)

    public constructor(name: String, isDaemon: Boolean) : this(name, Unit)

    public fun schedule(task: TimerTask, delay: Long) {
        scheduleInternal(task, delay, 0L, false)
    }

    public fun schedule(task: TimerTask, delay: Long, period: Long) {
        if (period <= 0L) throw IllegalArgumentException("period must be positive")
        scheduleInternal(task, delay, period, false)
    }

    public fun schedule(task: TimerTask, time: Date) {
        schedule(task, (time.getTime() - System.currentTimeMillis()).coerceAtLeast(0L))
    }

    public fun schedule(task: TimerTask, firstTime: Date, period: Long) {
        schedule(task, (firstTime.getTime() - System.currentTimeMillis()).coerceAtLeast(0L), period)
    }

    public fun scheduleAtFixedRate(task: TimerTask, delay: Long, period: Long) {
        if (period <= 0L) throw IllegalArgumentException("period must be positive")
        scheduleInternal(task, delay, period, true)
    }

    public fun scheduleAtFixedRate(task: TimerTask, firstTime: Date, period: Long) {
        if (period <= 0L) throw IllegalArgumentException("period must be positive")
        scheduleInternal(
            task,
            (firstTime.getTime() - System.currentTimeMillis()).coerceAtLeast(0L),
            period,
            true
        )
    }

    public fun cancel() {
        cancelled = true
        executor.shutdownNow()
    }

    public fun purge(): Int = 0

    private fun scheduleInternal(task: TimerTask, delay: Long, period: Long, fixedRate: Boolean) {
        if (delay < 0L) throw IllegalArgumentException("delay must not be negative")
        if (cancelled) throw IllegalStateException("Timer is cancelled")
        task.markScheduled()
        executor.execute(Runnable {
            if (delay > 0L) TimeUnit.MILLISECONDS.sleep(delay)
            var executionTime = System.currentTimeMillis() + delay
            while (!cancelled && !task.isCancelled) {
                task.runAt(executionTime)
                if (period == 0L || cancelled || task.isCancelled) break
                executionTime = if (fixedRate) {
                    executionTime + period
                } else {
                    System.currentTimeMillis() + period
                }
                val wait = executionTime - System.currentTimeMillis()
                if (wait > 0L) TimeUnit.MILLISECONDS.sleep(wait)
            }
            task.markFinished()
        })
    }
}

/** A task scheduled by [Timer]. Subclasses provide the task body. */
public abstract class TimerTask : Runnable {
    @Volatile
    internal var isCancelled: Boolean = false
        private set

    @Volatile
    private var scheduled: Boolean = false

    @Volatile
    private var finished: Boolean = false

    @Volatile
    private var executionTime: Long = 0L

    public abstract override fun run()

    public fun cancel(): Boolean {
        val wasPending = scheduled && !finished && !isCancelled
        isCancelled = true
        return wasPending
    }

    public fun scheduledExecutionTime(): Long = executionTime

    internal fun markScheduled() {
        if (scheduled || isCancelled) throw IllegalStateException("TimerTask is already scheduled or cancelled")
        scheduled = true
    }

    internal fun runAt(value: Long) {
        if (isCancelled) return
        executionTime = value
        run()
    }

    internal fun markFinished() {
        finished = true
    }
}
