@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class, kotlin.experimental.ExperimentalNativeApi::class)

package java.util

import java.lang.Runnable
import java.lang.Thread
import java.util.concurrent.TimeUnit
import kotlinx.atomicfu.locks.ParkingHandle
import kotlinx.atomicfu.locks.ParkingSupport
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlin.system.System
import kotlin.native.ref.WeakReference
import kotlin.time.Duration.Companion.milliseconds

private class TimerEntry(val task: TimerTask, var time: Long, val period: Long, val fixedRate: Boolean)

private object TimerNames {
    private val guard = SynchronizedObject()
    private var next = 0

    fun allocate(): String {
        guard.lock()
        try {
            val name = "Timer-${next}"
            next += 1
            return name
        } finally { guard.unlock() }
    }
}

private class TimerState {
    private val guard = SynchronizedObject()
    private val tasks = ArrayList<TimerEntry>()
    private var cancelled = false
    private var workerHandle: ParkingHandle? = null
    private var owner: WeakReference<Timer>? = null

    fun attach(timer: Timer) {
        owner = WeakReference(timer)
    }

    private fun ownerIsGone(): Boolean = owner?.value == null

    public fun schedule(task: TimerTask, delay: Long) = scheduleDelay(task, delay, 0L, false)
    public fun schedule(task: TimerTask, delay: Long, period: Long) {
        if (period <= 0L) throw IllegalArgumentException("period must be positive")
        scheduleDelay(task, delay, period, false)
    }
    public fun schedule(task: TimerTask, time: Date) = scheduleDate(task, time, 0L, false)
    public fun schedule(task: TimerTask, firstTime: Date, period: Long) {
        if (period <= 0L) throw IllegalArgumentException("period must be positive")
        scheduleDate(task, firstTime, period, false)
    }
    public fun scheduleAtFixedRate(task: TimerTask, delay: Long, period: Long) {
        if (period <= 0L) throw IllegalArgumentException("period must be positive")
        scheduleDelay(task, delay, period, true)
    }
    public fun scheduleAtFixedRate(task: TimerTask, firstTime: Date, period: Long) {
        if (period <= 0L) throw IllegalArgumentException("period must be positive")
        scheduleDate(task, firstTime, period, true)
    }
    private fun scheduleDelay(task: TimerTask, delay: Long, period: Long, fixedRate: Boolean) {
        if (delay < 0L) throw IllegalArgumentException("delay must not be negative")
        val now = System.currentTimeMillis()
        if (delay > Long.MAX_VALUE - now) throw IllegalArgumentException("execution time overflow")
        enqueue(task, now + delay, period, fixedRate)
    }
    private fun scheduleDate(task: TimerTask, date: Date, period: Long, fixedRate: Boolean) {
        val time = date.getTime()
        if (time < 0L) throw IllegalArgumentException("negative execution time")
        enqueue(task, time, period, fixedRate)
    }
    private fun enqueue(task: TimerTask, time: Long, period: Long, fixedRate: Boolean) {
        var wake: ParkingHandle? = null
        guard.lock()
        try {
            if (cancelled) throw IllegalStateException("Timer is cancelled")
            task.markScheduled()
            tasks.add(TimerEntry(task, time, period, fixedRate))
            wake = workerHandle
        } finally { guard.unlock() }
        if (wake != null) ParkingSupport.unpark(wake)
    }
    public fun cancel() {
        var wake: ParkingHandle? = null
        guard.lock()
        try {
            cancelled = true
            tasks.clear()
            wake = workerHandle
        } finally { guard.unlock() }
        if (wake != null) ParkingSupport.unpark(wake)
    }
    public fun purge(): Int {
        var count = 0
        guard.lock()
        try {
            var i = tasks.size - 1
            while (i >= 0) {
                if (tasks[i].task.isCancelled) { tasks.removeAt(i); count += 1 }
                i -= 1
            }
        } finally { guard.unlock() }
        return count
    }
    fun runLoop() {
        val handle = ParkingSupport.currentThreadHandle()
        guard.lock()
        try { workerHandle = handle } finally { guard.unlock() }
        while (true) {
            var entry: TimerEntry? = null
            var waitMillis = -1L
            guard.lock()
            try {
                if (cancelled) return
                var earliest = -1
                var i = 0
                while (i < tasks.size) {
                    if (tasks[i].task.isCancelled) { tasks.removeAt(i); continue }
                    if (earliest < 0 || tasks[i].time < tasks[earliest].time) earliest = i
                    i += 1
                }
                if (earliest >= 0) {
                    val candidate = tasks[earliest]
                    val now = System.currentTimeMillis()
                    if (candidate.time <= now) entry = tasks.removeAt(earliest)
                    else waitMillis = candidate.time - now
                } else if (ownerIsGone()) {
                    return
                }
            } finally { guard.unlock() }
            if (entry == null) {
                // Recheck an idle timer's weak owner even if no task wakes it.
                ParkingSupport.park(if (waitMillis < 0L) 100L.milliseconds else waitMillis.milliseconds)
                continue
            }
            val task = entry.task
            val startedAt = System.currentTimeMillis()
            try {
                val scheduledTime = if (entry.period != 0L && !entry.fixedRate) startedAt else entry.time
                if (task.prepareRun(scheduledTime, entry.period != 0L)) task.run()
            } catch (exception: Throwable) {
                cancel()
                throw exception
            }
            if (entry.period != 0L && !task.isCancelled) {
                val previous = if (entry.fixedRate) entry.time else startedAt
                entry.time = if (entry.period > Long.MAX_VALUE - previous) Long.MAX_VALUE else previous + entry.period
                guard.lock()
                try { if (!cancelled && !task.isCancelled) tasks.add(entry) } finally { guard.unlock() }
            }
        }
    }
}
public class Timer private constructor(name: String?, isDaemon: Boolean, marker: Unit) {
    private val state = TimerState()

    init {
        // The worker must not retain its Timer: the state has an independent lifetime.
        val workerState = state
        workerState.attach(this)
        val worker = Thread(Runnable { workerState.runLoop() }, name ?: TimerNames.allocate())
        worker.isDaemon = isDaemon
        worker.start()
    }

    public constructor() : this(null, false, Unit)
    public constructor(isDaemon: Boolean) : this(null, isDaemon, Unit)
    public constructor(name: String) : this(name, false, Unit)
    public constructor(name: String, isDaemon: Boolean) : this(name, isDaemon, Unit)

    public fun schedule(task: TimerTask, delay: Long) = state.schedule(task, delay)
    public fun schedule(task: TimerTask, delay: Long, period: Long) = state.schedule(task, delay, period)
    public fun schedule(task: TimerTask, time: Date) = state.schedule(task, time)
    public fun schedule(task: TimerTask, firstTime: Date, period: Long) = state.schedule(task, firstTime, period)
    public fun scheduleAtFixedRate(task: TimerTask, delay: Long, period: Long) = state.scheduleAtFixedRate(task, delay, period)
    public fun scheduleAtFixedRate(task: TimerTask, firstTime: Date, period: Long) = state.scheduleAtFixedRate(task, firstTime, period)
    public fun cancel() = state.cancel()
    public fun purge(): Int = state.purge()
}

/** A task scheduled by [Timer]. Subclasses provide the task body. */
public abstract class TimerTask : Runnable {
    private val guard = SynchronizedObject()
    private var cancelled = false
    internal val isCancelled: Boolean
        get() {
            guard.lock()
            try { return cancelled } finally { guard.unlock() }
        }
    private var scheduled: Boolean = false
    private var finished: Boolean = false
    private var executionTime: Long = 0L

    public abstract override fun run()

    public fun cancel(): Boolean {
        guard.lock()
        try {
            val wasPending = scheduled && !finished && !cancelled
            cancelled = true
            return wasPending
        } finally { guard.unlock() }
    }

    public fun scheduledExecutionTime(): Long {
        guard.lock()
        try { return executionTime } finally { guard.unlock() }
    }

    internal fun markScheduled() {
        guard.lock()
        try {
            if (scheduled || cancelled) throw IllegalStateException("TimerTask is already scheduled or cancelled")
            scheduled = true
        } finally { guard.unlock() }
    }

    internal fun prepareRun(value: Long, periodic: Boolean): Boolean {
        guard.lock()
        try {
            if (cancelled) return false
            executionTime = value
            if (!periodic) finished = true
            return true
        } finally { guard.unlock() }
    }
}
