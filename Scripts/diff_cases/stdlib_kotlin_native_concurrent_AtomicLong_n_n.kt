// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_concurrent_AtomicLong_n_n.expected.stdout
// Candidate-only: kotlin.native.concurrent APIs are unavailable in JVM kotlinc.
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.AtomicLong

fun main() {
    AtomicLong()
    AtomicLong(42L)
}
