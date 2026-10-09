/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/jvm/src/channels/TickerChannels.kt>.
 */

package kotlinx.coroutines.channels

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.time.DurationUnit
import kotlin.time.TimeSource
import kotlin.time.absoluteValue
import kotlin.time.inWholeNanoseconds
import kotlin.time.isNegative
import kotlin.time.toDuration
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.ObsoleteCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@ObsoleteCoroutinesApi
public enum class TickerMode {
    FIXED_PERIOD,
    FIXED_DELAY
}

@ObsoleteCoroutinesApi
@OptIn(DelicateCoroutinesApi::class)
public fun ticker(
    delayMillis: Long,
    initialDelayMillis: Long = delayMillis,
    context: CoroutineContext = EmptyCoroutineContext,
    mode: TickerMode = TickerMode.FIXED_PERIOD
): ReceiveChannel<Unit> {
    require(delayMillis >= 0L) { "Expected non-negative delay, but has $delayMillis ms" }
    require(initialDelayMillis >= 0L) {
        "Expected non-negative initial delay, but has $initialDelayMillis ms"
    }

    val channel = Channel<Unit>(0)
    val job = GlobalScope.launch(context = Dispatchers.Unconfined + context, start = CoroutineStart.DEFAULT) {
        try {
            when (mode) {
                TickerMode.FIXED_PERIOD -> fixedPeriodTicker(channel, delayMillis, initialDelayMillis)
                TickerMode.FIXED_DELAY -> fixedDelayTicker(channel, delayMillis, initialDelayMillis)
            }
        } finally {
            channel.close()
        }
    }
    channel.invokeOnClose { job.cancel() }
    return channel
}

private suspend fun fixedPeriodTicker(
    channel: SendChannel<Unit>,
    delayMillis: Long,
    initialDelayMillis: Long
) {
    val period = delayMillis.toDuration(DurationUnit.MILLISECONDS)
    var deadline = TimeSource.Monotonic.markNow() + initialDelayMillis.toDuration(DurationUnit.MILLISECONDS)
    delay(initialDelayMillis)

    while (true) {
        deadline += period
        channel.send(Unit)

        val now = TimeSource.Monotonic.markNow()
        var nextDelay = deadline - now
        if (nextDelay.isNegative() && delayMillis > 0L) {
            val periodNanos = period.inWholeNanoseconds
            val lateNanos = nextDelay.absoluteValue.inWholeNanoseconds
            val adjustedNanos = periodNanos - lateNanos % periodNanos
            nextDelay = adjustedNanos.toDuration(DurationUnit.NANOSECONDS)
            deadline = now + nextDelay
        }
        delay(nextDelay)
    }
}

private suspend fun fixedDelayTicker(
    channel: SendChannel<Unit>,
    delayMillis: Long,
    initialDelayMillis: Long
) {
    delay(initialDelayMillis)
    while (true) {
        channel.send(Unit)
        delay(delayMillis)
    }
}
