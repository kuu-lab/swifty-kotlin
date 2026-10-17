package kotlin.time

// Migration source: Sources/Runtime/RuntimeInstant.swift (kk_clock_system_now)
//
// Clock.System is a nested object, so its now() factory is expressed as a
// Kotlin-source extension on that object.

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_clock_system_now")
private external fun __kk_clock_system_now(): Instant

public fun Clock.System.now(): Instant = __kk_clock_system_now()
