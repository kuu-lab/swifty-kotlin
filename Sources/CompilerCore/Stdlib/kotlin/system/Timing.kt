package kotlin.system

import kotlin.internal.KsSymbolName

// KSP-617
// Public kotlin.system timing layer migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeSystem.swift (kk_system_getTime*),
// now the demoted __kk_system_getTime* OS bridges. measureTime* used to be
// expanded by a KIR special case (StdlibSpecialCallKind); they are plain
// Kotlin inline functions here, matching kotlin-stdlib.

// Clock getters are internal bridges, not public Kotlin API.
// PublishedApi allows the supported public inline functions to read the clocks
// without exposing implementation-specific function names.
@KsSymbolName("__kk_system_getTimeMillis")
@PublishedApi
internal external fun __kkSystemGetTimeMillis(): Long

@KsSymbolName("__kk_system_getTimeMicros")
@PublishedApi
internal external fun __kkSystemGetTimeMicros(): Long

@KsSymbolName("__kk_system_getTimeNanos")
@PublishedApi
internal external fun __kkSystemGetTimeNanos(): Long

public inline fun measureTimeMillis(block: () -> Unit): Long {
    val start = __kkSystemGetTimeMillis()
    block()
    return __kkSystemGetTimeMillis() - start
}

public inline fun measureTimeMicros(block: () -> Unit): Long {
    val start = __kkSystemGetTimeMicros()
    block()
    return __kkSystemGetTimeMicros() - start
}

public inline fun measureNanoTime(block: () -> Unit): Long {
    val start = __kkSystemGetTimeNanos()
    block()
    return __kkSystemGetTimeNanos() - start
}
