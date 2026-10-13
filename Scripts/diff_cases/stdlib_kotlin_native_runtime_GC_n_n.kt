// CANDIDATE-ONLY
@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

import kotlin.native.runtime.GC

fun main() {
    val processor: GC.MainThreadFinalizerProcessor? = null
    println(processor == null)
}
