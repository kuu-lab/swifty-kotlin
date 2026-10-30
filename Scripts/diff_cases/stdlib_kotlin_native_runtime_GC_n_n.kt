// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_runtime_GC_n_n.expected.stdout
@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

import kotlin.native.runtime.GC

fun main() {
    val processor: GC.MainThreadFinalizerProcessor? = null
    println(processor == null)
}
