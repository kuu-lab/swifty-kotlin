package kotlin.concurrent

import java.util.Date
import java.util.Timer
import java.util.TimerTask

public inline fun Timer.schedule(
    delay: Long,
    crossinline action: TimerTask.() -> Unit
): TimerTask = scheduleTimerTask(this, timerTask(action), delay)

public inline fun Timer.schedule(
    delay: Long,
    period: Long,
    crossinline action: TimerTask.() -> Unit
): TimerTask = scheduleTimerTask(this, timerTask(action), delay, period)

public inline fun Timer.schedule(
    time: Date,
    crossinline action: TimerTask.() -> Unit
): TimerTask = scheduleTimerTask(this, timerTask(action), time)

public inline fun Timer.schedule(
    time: Date,
    period: Long,
    crossinline action: TimerTask.() -> Unit
): TimerTask = scheduleTimerTask(this, timerTask(action), time, period)

public inline fun Timer.scheduleAtFixedRate(
    delay: Long,
    period: Long,
    crossinline action: TimerTask.() -> Unit
): TimerTask = scheduleTimerTaskAtFixedRate(this, timerTask(action), delay, period)

public inline fun Timer.scheduleAtFixedRate(
    time: Date,
    period: Long,
    crossinline action: TimerTask.() -> Unit
): TimerTask = scheduleTimerTaskAtFixedRate(this, timerTask(action), time, period)

public inline fun timerTask(crossinline action: TimerTask.() -> Unit): TimerTask =
    object : TimerTask() {
        override fun run() {
            action()
        }
    }

@PublishedApi
internal fun scheduleTimerTask(timer: Timer, task: TimerTask, delay: Long): TimerTask {
    timer.schedule(task, delay)
    return task
}

@PublishedApi
internal fun scheduleTimerTask(timer: Timer, task: TimerTask, delay: Long, period: Long): TimerTask {
    timer.schedule(task, delay, period)
    return task
}

@PublishedApi
internal fun scheduleTimerTask(timer: Timer, task: TimerTask, time: Date): TimerTask {
    timer.schedule(task, time)
    return task
}

@PublishedApi
internal fun scheduleTimerTask(timer: Timer, task: TimerTask, time: Date, period: Long): TimerTask {
    timer.schedule(task, time, period)
    return task
}

@PublishedApi
internal fun scheduleTimerTaskAtFixedRate(timer: Timer, task: TimerTask, delay: Long, period: Long): TimerTask {
    timer.scheduleAtFixedRate(task, delay, period)
    return task
}

@PublishedApi
internal fun scheduleTimerTaskAtFixedRate(timer: Timer, task: TimerTask, time: Date, period: Long): TimerTask {
    timer.scheduleAtFixedRate(task, time, period)
    return task
}

@PublishedApi
internal fun newTimer(name: String?, daemon: Boolean): Timer =
    if (name == null) Timer(daemon) else Timer(name, daemon)

public inline fun timer(
    name: String? = null, daemon: Boolean = false, initialDelay: Long = 0L,
    period: Long, crossinline action: TimerTask.() -> Unit
): Timer {
    val result = newTimer(name, daemon)
    result.schedule(initialDelay, period, action)
    return result
}

public inline fun timer(
    name: String? = null, daemon: Boolean = false, startAt: Date,
    period: Long, crossinline action: TimerTask.() -> Unit
): Timer {
    val result = newTimer(name, daemon)
    result.schedule(startAt, period, action)
    return result
}

public inline fun fixedRateTimer(
    name: String? = null, daemon: Boolean = false, initialDelay: Long = 0L,
    period: Long, crossinline action: TimerTask.() -> Unit
): Timer {
    val result = newTimer(name, daemon)
    result.scheduleAtFixedRate(initialDelay, period, action)
    return result
}

public inline fun fixedRateTimer(
    name: String? = null, daemon: Boolean = false, startAt: Date,
    period: Long, crossinline action: TimerTask.() -> Unit
): Timer {
    val result = newTimer(name, daemon)
    result.scheduleAtFixedRate(startAt, period, action)
    return result
}
