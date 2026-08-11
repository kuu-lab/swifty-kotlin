package kotlin.time

// KSP-472
// measureTime / measureTimedValue.
// Migration source: Sources/Runtime/RuntimeDuration.swift
//   kk_measureTime, kk_measureTimedValue
//
// Both functions are ordinary inline functions here; the monotonic clock
// (syscall) and the TimedValue allocation (object representation) are the only
// pieces that stay native, reached through the __kk_* bridges below.

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_system_nanoTime")
@PublishedApi
internal external fun __kk_system_nanoTime(): Long

@KsSymbolName("kk_timedvalue_new")
@PublishedApi
internal external fun __kk_timedvalue_new(value: Any?, duration: Duration): TimedValue

public inline fun measureTime(block: () -> Unit): Duration {
    val start = __kk_system_nanoTime()
    block()
    return (__kk_system_nanoTime() - start).nanoseconds
}

public inline fun measureTimedValue(block: () -> Any?): TimedValue {
    val start = __kk_system_nanoTime()
    val value = block()
    val elapsed = (__kk_system_nanoTime() - start).nanoseconds
    return __kk_timedvalue_new(value, elapsed)
}
