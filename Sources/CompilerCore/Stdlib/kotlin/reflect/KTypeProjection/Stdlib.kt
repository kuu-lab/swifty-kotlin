package kotlin.reflect

import kotlin.internal.KsSymbolName

// KSP-1334: the constructor allocates the runtime reflection box and keeps
// Kotlin's nullable-pair validation in the native runtime bridge.
public class KTypeProjection {
    @KsSymbolName("__kk_ktypeprojection_create_checked")
    public constructor(variance: KVariance?, type: KType?)

    public companion object {}
}
