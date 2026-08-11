package kotlin.system

import kotlin.internal.KsSymbolName

// KSP-617
// Public kotlin.system timing layer migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeSystem.swift (kk_system_getTime*),
// now the demoted __kk_system_getTime* OS bridges. measureTime* used to be
// expanded by a KIR special case (StdlibSpecialCallKind); they are plain
// Kotlin inline functions here, matching kotlin-stdlib.

@KsSymbolName("__kk_system_getTimeMillis")
private external fun __kkSystemGetTimeMillis(): Long

@KsSymbolName("__kk_system_getTimeMicros")
private external fun __kkSystemGetTimeMicros(): Long

@KsSymbolName("__kk_system_getTimeNanos")
private external fun __kkSystemGetTimeNanos(): Long

public fun getTimeMillis(): Long = __kkSystemGetTimeMillis()

public fun getTimeMicros(): Long = __kkSystemGetTimeMicros()

public fun getTimeNanos(): Long = __kkSystemGetTimeNanos()

public inline fun measureTimeMillis(block: () -> Unit): Long {
    val start = getTimeMillis()
    block()
    return getTimeMillis() - start
}

public inline fun measureTimeMicros(block: () -> Unit): Long {
    val start = getTimeMicros()
    block()
    return getTimeMicros() - start
}

public inline fun measureNanoTime(block: () -> Unit): Long {
    val start = getTimeNanos()
    block()
    return getTimeNanos() - start
}
