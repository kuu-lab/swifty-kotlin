package kotlin.system

import kotlin.internal.KsSymbolName

// KSP-617
// Public kotlin.system timing layer migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeSystem.swift (kk_system_getTime*),
// now the demoted __kk_system_getTime* OS bridges. measureTime* used to be
// expanded by a KIR special case (StdlibSpecialCallKind); they are plain
// Kotlin inline functions here, matching kotlin-stdlib.

// getTimeMillis/getTimeNanos are not part of the Kotlin/JVM public API.
// PublishedApi allows the supported public inline functions to read the clocks
// without exposing the removed public function names.
@KsSymbolName("__kk_system_getTimeMillis")
@PublishedApi
internal external fun __kkSystemGetTimeMillis(): Long

@KsSymbolName("__kk_system_getTimeMicros")
private external fun __kkSystemGetTimeMicros(): Long

@KsSymbolName("__kk_system_getTimeNanos")
@PublishedApi
internal external fun __kkSystemGetTimeNanos(): Long

public fun getTimeMicros(): Long = __kkSystemGetTimeMicros()

public inline fun measureTimeMillis(block: () -> Unit): Long {
    val start = __kkSystemGetTimeMillis()
    block()
    return __kkSystemGetTimeMillis() - start
}

public inline fun measureTimeMicros(block: () -> Unit): Long {
    val start = getTimeMicros()
    block()
    return getTimeMicros() - start
}

public inline fun measureNanoTime(block: () -> Unit): Long {
    val start = __kkSystemGetTimeNanos()
    block()
    return __kkSystemGetTimeNanos() - start
}
