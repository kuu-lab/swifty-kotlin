// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_concurrent_AtomicInt_n_n.expected.stdout
// Candidate-only: JVM kotlinc has no Kotlin/Native AtomicInt oracle (DEBT-DIFF-001).
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.AtomicInt

fun main() {
    AtomicInt(42)
}
