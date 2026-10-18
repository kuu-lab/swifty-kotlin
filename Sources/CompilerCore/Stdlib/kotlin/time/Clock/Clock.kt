package kotlin.time

import kotlin.internal.KsSymbolName

// The runtime bridge remains explicit because TimeSource.asClock creates a
// compiler/runtime clock object.
public interface Clock {
    @KsSymbolName("kk_clock_now")
    public external fun now(): Instant
}
