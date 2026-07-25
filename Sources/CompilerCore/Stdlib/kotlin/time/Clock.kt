package kotlin.time

// KSP-472
// Clock.System.now() factory.
// Migration source: Sources/Runtime/RuntimeInstant.swift (kk_clock_system_now)
//
// Clock.System is a nested object, so its now() factory is expressed as a
// Kotlin-source extension on that object. The implementation delegates to the
// __kk_clock_system_now bridge, which is backed by the kk_clock_system_now ABI.

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_clock_system_now")
private external fun __kk_clock_system_now(): Instant

public fun Clock.System.now(): Instant = __kk_clock_system_now()
