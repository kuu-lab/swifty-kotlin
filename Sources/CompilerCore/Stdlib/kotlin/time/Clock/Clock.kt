package kotlin.time

import kotlin.internal.KsSymbolName

// The runtime bridge remains explicit because TimeSource.asClock creates a
// compiler/runtime clock object.
public interface Clock {
    @KsSymbolName("kk_clock_now")
    public external fun now(): Instant

    // Upstream shape (kotlin-stdlib kotlin/time/Clock.kt): Clock.System is a
    // real nested object implementing Clock, so Clock-typed receivers
    // dispatch now() through the object's own itable entry.
    public object System : Clock {
        override fun now(): Instant = __kk_clock_system_now()
    }
}

@KsSymbolName("kk_clock_system_now")
private external fun __kk_clock_system_now(): Instant
