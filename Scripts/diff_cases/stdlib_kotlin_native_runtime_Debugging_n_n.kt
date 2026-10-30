// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_runtime_Debugging_n_n.expected.stdout
// Candidate-only: kotlin.native.runtime APIs are Kotlin/Native-only and have no JVM reference output.
@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

import kotlin.native.runtime.Debugging

fun debuggingSingleton(): Debugging = Debugging

fun main() {
    println(debuggingSingleton() === Debugging)
}
