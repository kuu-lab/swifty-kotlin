// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_concurrent_AtomicReference_n_n.expected.stdout
// Candidate-only: kotlin.concurrent atomic APIs have no JVM reference in Kotlin 2.3.10.

import kotlin.concurrent.AtomicReference

fun main() {
    val atomic = AtomicReference("initial")
    println(atomic.value)
    println(atomic.toString())
}
