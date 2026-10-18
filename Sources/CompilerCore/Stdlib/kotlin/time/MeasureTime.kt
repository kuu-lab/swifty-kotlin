package kotlin.time

import kotlin.time.Duration.Companion.nanoseconds

// Migration source: Sources/Runtime/RuntimeDuration.swift
//
// The monotonic clock (syscall) is the only piece that stays native, reached
// through the __kk_* bridge below.

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_system_nanoTime")
@PublishedApi
internal external fun __kk_system_nanoTime(): Long

public inline fun measureTime(block: () -> Unit): Duration {
    val start = __kk_system_nanoTime()
    block()
    return (__kk_system_nanoTime() - start).nanoseconds
}

public inline fun measureTimedValue(block: () -> Any?): TimedValue<Any?> {
    val start = __kk_system_nanoTime()
    val value = block()
    val elapsed = (__kk_system_nanoTime() - start).nanoseconds
    return TimedValue(value, elapsed)
}
